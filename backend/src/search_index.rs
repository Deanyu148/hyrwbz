use crate::db::Db;
use crate::models::Task;
use crate::service;
use anyhow::Result;
use sqlx::sqlite::{
    SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous,
};
use sqlx::{Pool, Row, Sqlite};
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;

#[derive(Debug, Clone, PartialEq, Eq)]
struct SearchTerm {
    value: String,
    excluded: bool,
}

#[derive(Clone)]
pub struct SearchIndex {
    db: Pool<Sqlite>,
    dirty: Arc<AtomicBool>,
    rebuild_lock: Arc<Mutex<()>>,
}

impl SearchIndex {
    pub async fn open(core_db: &Db) -> Result<Self> {
        let path = search_index_db_path();
        match Self::open_at(core_db, &path).await {
            Ok(index) => Ok(index),
            Err(first_error) => {
                // 搜索库是可重建缓存；损坏时清理缓存后自动恢复，不阻塞主数据库启动。
                std::fs::remove_file(&path).ok();
                std::fs::remove_file(format!("{path}-wal")).ok();
                std::fs::remove_file(format!("{path}-shm")).ok();
                Self::open_at(core_db, &path)
                    .await
                    .map_err(|second_error| anyhow::anyhow!("{first_error}; rebuild failed: {second_error}"))
            }
        }
    }

    pub(crate) async fn open_at(core_db: &Db, path: &str) -> Result<Self> {
        if let Some(parent) = Path::new(path).parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let options = SqliteConnectOptions::from_str(&format!("sqlite://{}", path))?
            .create_if_missing(true)
            .journal_mode(SqliteJournalMode::Wal)
            .synchronous(SqliteSynchronous::Normal)
            .busy_timeout(Duration::from_secs(10));
        let db = SqlitePoolOptions::new()
            .min_connections(1)
            .max_connections(2)
            .connect_with(options)
            .await?;
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS task_search_documents (
                task_id INTEGER PRIMARY KEY,
                content TEXT NOT NULL
            )",
        )
        .execute(&db)
        .await?;
        let index = Self {
            db,
            dirty: Arc::new(AtomicBool::new(true)),
            rebuild_lock: Arc::new(Mutex::new(())),
        };
        index.ensure_fresh(core_db).await?;
        Ok(index)
    }

    pub fn invalidate(&self) {
        self.dirty.store(true, Ordering::Release);
    }

    pub async fn search_task_ids(&self, core_db: &Db, query: &str) -> Result<Vec<i64>> {
        self.ensure_fresh(core_db).await?;
        let terms = parse_search_query(query);
        let mut sql = String::from("SELECT task_id FROM task_search_documents");
        if !terms.is_empty() {
            sql.push_str(" WHERE ");
            for (index, term) in terms.iter().enumerate() {
                if index > 0 {
                    sql.push_str(" AND ");
                }
                if term.excluded {
                    sql.push_str("content NOT LIKE ? ESCAPE '\\'");
                } else {
                    sql.push_str("content LIKE ? ESCAPE '\\'");
                }
            }
        }
        sql.push_str(" ORDER BY task_id");
        let query = terms.iter().fold(sqlx::query(&sql), |query, term| {
            query.bind(format!("%{}%", escape_like(&term.value)))
        });
        let rows = query.fetch_all(&self.db).await?;
        Ok(rows
            .into_iter()
            .filter_map(|row| row.try_get("task_id").ok())
            .collect())
    }

    async fn ensure_fresh(&self, core_db: &Db) -> Result<()> {
        if !self.dirty.load(Ordering::Acquire) {
            return Ok(());
        }
        let _guard = self.rebuild_lock.lock().await;
        loop {
            if !self.dirty.swap(false, Ordering::AcqRel) {
                return Ok(());
            }
            if let Err(error) = self.rebuild(core_db).await {
                self.dirty.store(true, Ordering::Release);
                return Err(error);
            }
            // 数据若在重建期间再次变化，立即按最新状态再构建一次，避免
            // 并发写入导致失效标记被覆盖。
            if !self.dirty.load(Ordering::Acquire) {
                return Ok(());
            }
        }
    }

    async fn rebuild(&self, core_db: &Db) -> Result<()> {
        let tasks = service::list_tasks(core_db, &crate::models::FilterReq::default())
            .await
            .map_err(|error| anyhow::anyhow!(error.message))?;
        let mut tx = self.db.begin().await?;
        sqlx::query("DELETE FROM task_search_documents")
            .execute(&mut *tx)
            .await?;
        for task in tasks {
            sqlx::query(
                "INSERT INTO task_search_documents (task_id, content) VALUES (?1, ?2)",
            )
            .bind(task.id)
            .bind(task_search_document(&task))
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }
}

fn task_search_document(task: &Task) -> String {
    let mut values = vec![
        task.meeting_no.clone(),
        task.task_no.to_string(),
        task.task_desc.clone(),
        task.dept.clone(),
        task.owner.clone(),
        task.required_date.clone(),
        task.actual_date.clone(),
        task.remark.clone(),
        if task.has_attachment {
            "有附件".to_string()
        } else {
            "无附件".to_string()
        },
    ];
    for delay in &task.delays {
        values.push(delay.delay_date.clone());
        values.push(delay.delay_reason.clone());
    }
    values.join("\n").to_lowercase()
}

fn parse_search_query(query: &str) -> Vec<SearchTerm> {
    let chars: Vec<char> = query.trim().chars().collect();
    let mut terms = Vec::new();
    let mut index = 0;
    while index < chars.len() {
        while index < chars.len() && chars[index].is_whitespace() {
            index += 1;
        }
        if index >= chars.len() {
            break;
        }
        let excluded = chars[index] == '-';
        if excluded {
            index += 1;
        }
        if index >= chars.len() {
            break;
        }
        let quote = matches!(chars[index], '"' | '\'').then_some(chars[index]);
        if quote.is_some() {
            index += 1;
        }
        let start = index;
        if let Some(quote) = quote {
            while index < chars.len() && chars[index] != quote {
                index += 1;
            }
        } else {
            while index < chars.len() && !chars[index].is_whitespace() {
                index += 1;
            }
        }
        let value: String = chars[start..index]
            .iter()
            .collect::<String>()
            .trim()
            .to_lowercase();
        if !value.is_empty() && value != "-" {
            terms.push(SearchTerm { value, excluded });
        }
        if quote.is_some() && index < chars.len() {
            index += 1;
        }
    }
    terms
}

fn escape_like(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_")
}

fn search_index_db_path() -> String {
    let exe = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    exe.parent()
        .unwrap_or_else(|| Path::new("."))
        .join("search_index.db")
        .to_string_lossy()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parser_supports_terms_phrases_and_exclusions() {
        assert_eq!(
            parse_search_query("工程 \"张 三\" -已完成"),
            vec![
                SearchTerm {
                    value: "工程".to_string(),
                    excluded: false,
                },
                SearchTerm {
                    value: "张 三".to_string(),
                    excluded: false,
                },
                SearchTerm {
                    value: "已完成".to_string(),
                    excluded: true,
                },
            ]
        );
    }

    #[test]
    fn document_contains_task_delay_and_attachment_fields() {
        let task = Task {
            id: 1,
            meeting_no: "纪要〔2026〕1号".to_string(),
            task_no: 2,
            task_desc: "推进工程".to_string(),
            dept: "建设部".to_string(),
            owner: "张三".to_string(),
            required_date: "2026/09/10".to_string(),
            actual_date: "进行中".to_string(),
            remark: "重点".to_string(),
            created_at: String::new(),
            updated_at: String::new(),
            has_attachment: true,
            delays: vec![crate::models::Delay {
                id: 1,
                task_id: 1,
                meeting_no: String::new(),
                task_no: 2,
                delay_date: "2026/09/20".to_string(),
                delay_reason: "等待材料".to_string(),
                created_at: String::new(),
            }],
        };
        let document = task_search_document(&task);
        for value in ["推进工程", "建设部", "张三", "有附件", "等待材料"] {
            assert!(document.contains(value));
        }
    }

    #[tokio::test]
    async fn separate_index_rebuilds_after_invalidation() {
        let unique = uuid::Uuid::new_v4();
        let core_path = std::env::temp_dir().join(format!("hyrwbz_search_core_{unique}.db"));
        let index_path = std::env::temp_dir().join(format!("hyrwbz_search_index_{unique}.db"));
        let core_db = crate::db::init(core_path.to_string_lossy().as_ref())
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO tasks
             (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark)
             VALUES ('纪要〔2026〕1号', 1, '推进重点工程', '建设部', '张三', '', '进行中', '')",
        )
        .execute(&core_db)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO tasks
             (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark)
             VALUES ('纪要〔2026〕2号', 1, '普通任务', '综合部', '李四', '', '进行中', '')",
        )
        .execute(&core_db)
        .await
        .unwrap();

        let index = SearchIndex::open_at(&core_db, index_path.to_string_lossy().as_ref())
            .await
            .unwrap();
        assert!(index_path.is_file());
        assert_eq!(
            index.search_task_ids(&core_db, "工程 张三").await.unwrap(),
            vec![1]
        );
        assert_eq!(
            index
                .search_task_ids(&core_db, "工程 -综合部")
                .await
                .unwrap(),
            vec![1]
        );

        sqlx::query("UPDATE tasks SET task_desc = '已调整事项', updated_at = 'changed' WHERE id = 1")
            .execute(&core_db)
            .await
            .unwrap();
        index.invalidate();
        assert_eq!(
            index.search_task_ids(&core_db, "已调整").await.unwrap(),
            vec![1]
        );

        index.db.close().await;
        core_db.close().await;
        for path in [&core_path, &index_path] {
            std::fs::remove_file(path).ok();
            std::fs::remove_file(format!("{}-wal", path.to_string_lossy())).ok();
            std::fs::remove_file(format!("{}-shm", path.to_string_lossy())).ok();
        }
    }
}
