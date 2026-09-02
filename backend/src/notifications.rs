use crate::db::Db;
use crate::models::{FilterReq, Task};
use crate::service;
use anyhow::Result;
use chrono::{Local, NaiveDate};
use serde::Serialize;
use sqlx::{Pool, Row, Sqlite};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;
use tokio::sync::Mutex;

pub const REFRESH_INTERVAL: std::time::Duration = std::time::Duration::from_secs(30);

#[derive(Debug, Clone, Serialize)]
pub struct Notification {
    pub id: i64,
    pub task_id: i64,
    pub meeting_no: String,
    pub task_no: i64,
    pub expected_date: String,
    pub remaining_days: i64,
    pub message: String,
    pub notification_date: String,
    pub is_read: bool,
}

#[derive(Clone)]
pub struct NotificationStore {
    db: Pool<Sqlite>,
    refresh_lock: Arc<Mutex<()>>,
}

impl NotificationStore {
    pub async fn open() -> Result<Self> {
        let path = notification_db_path();
        Self::open_at(&path).await
    }

    async fn open_at(path: &str) -> Result<Self> {
        if let Some(parent) = Path::new(path).parent() {
            std::fs::create_dir_all(parent).ok();
        }
        let db = sqlx::sqlite::SqlitePoolOptions::new()
            .max_connections(2)
            .connect_with(
                sqlx::sqlite::SqliteConnectOptions::from_str(&format!("sqlite://{}", path))?
                    .create_if_missing(true),
            )
            .await?;
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS notifications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                source_key TEXT NOT NULL,
                meeting_no TEXT NOT NULL,
                task_no INTEGER NOT NULL,
                expected_date TEXT NOT NULL,
                remaining_days INTEGER NOT NULL,
                message TEXT NOT NULL,
                notification_date TEXT NOT NULL,
                is_read INTEGER NOT NULL DEFAULT 0
            )",
        )
        .execute(&db)
        .await?;
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS notification_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                task_id INTEGER NOT NULL,
                source_key TEXT NOT NULL,
                meeting_no TEXT NOT NULL,
                task_no INTEGER NOT NULL,
                expected_date TEXT NOT NULL,
                remaining_days INTEGER NOT NULL,
                message TEXT NOT NULL,
                notification_date TEXT NOT NULL,
                is_read INTEGER NOT NULL DEFAULT 0,
                UNIQUE(task_id, expected_date, notification_date)
            )",
        )
        .execute(&db)
        .await?;
        sqlx::query(
            "CREATE TABLE IF NOT EXISTS notification_read_state (
                task_id INTEGER NOT NULL,
                source_key TEXT NOT NULL,
                expected_date TEXT NOT NULL,
                notification_date TEXT NOT NULL,
                is_read INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(task_id, source_key, expected_date, notification_date)
            )",
        )
        .execute(&db)
        .await?;
        ensure_source_key_column(&db, "notifications").await?;
        ensure_source_key_column(&db, "notification_history").await?;
        Ok(Self {
            db,
            refresh_lock: Arc::new(Mutex::new(())),
        })
    }

    pub async fn refresh(&self, core_db: &Db) -> Result<()> {
        let _guard = self.refresh_lock.lock().await;
        let today = Local::now().date_naive();
        // 始终扫描核心数据库中的全部任务，不受主界面当前筛选条件影响。
        let mut tasks = service::list_tasks(core_db, &FilterReq::default())
            .await
            .map_err(|error| anyhow::anyhow!(error.message))?;
        sort_tasks_for_sequence(&mut tasks);
        let sequence_by_task_id: HashMap<i64, i64> = tasks
            .iter()
            .enumerate()
            .map(|(index, task)| (task.id, index as i64 + 1))
            .collect();
        let mut tx = self.db.begin().await?;
        sqlx::query("DELETE FROM notifications")
            .execute(&mut *tx)
            .await?;
        for (index, task) in tasks.into_iter().enumerate() {
            let sequence_no = index as i64 + 1;
            let Some((expected_date, remaining_days, message)) =
                build_notification(&task, sequence_no, today)
            else {
                continue;
            };
            let notification_date = today.format("%Y-%m-%d").to_string();
            let source_key = notification_source_key(&task);
            let old_read: Option<i64> = sqlx::query_scalar(
                "SELECT is_read FROM notification_read_state
                 WHERE task_id = ?1 AND expected_date = ?2 AND notification_date = ?3
                   AND source_key = ?4",
            )
            .bind(task.id)
            .bind(&expected_date)
            .bind(&notification_date)
            .bind(&source_key)
            .fetch_optional(&mut *tx)
            .await?;
            let is_read = old_read.unwrap_or(0) != 0;
            sqlx::query(
                "INSERT INTO notification_read_state
                 (task_id, source_key, expected_date, notification_date, is_read)
                 VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(task_id, source_key, expected_date, notification_date)
                 DO UPDATE SET is_read = excluded.is_read",
            )
            .bind(task.id)
            .bind(&source_key)
            .bind(&expected_date)
            .bind(&notification_date)
            .bind(if is_read { 1 } else { 0 })
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "INSERT INTO notification_history
                 (task_id, source_key, meeting_no, task_no, expected_date, remaining_days, message, notification_date, is_read)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
                 ON CONFLICT(task_id, expected_date, notification_date) DO UPDATE SET
                   source_key = excluded.source_key,
                   meeting_no = excluded.meeting_no,
                   task_no = excluded.task_no,
                   remaining_days = excluded.remaining_days,
                   message = excluded.message,
                   is_read = excluded.is_read",
            )
            .bind(task.id)
            .bind(&source_key)
            .bind(&task.meeting_no)
            .bind(task.task_no)
            .bind(&expected_date)
            .bind(remaining_days)
            .bind(&message)
            .bind(&notification_date)
            .bind(if is_read { 1 } else { 0 })
            .execute(&mut *tx)
            .await?;
            let notification_id: i64 = sqlx::query_scalar(
                "SELECT id FROM notification_history
                 WHERE task_id = ?1 AND expected_date = ?2 AND notification_date = ?3",
            )
            .bind(task.id)
            .bind(&expected_date)
            .bind(&notification_date)
            .fetch_one(&mut *tx)
            .await?;
            sqlx::query(
                "INSERT INTO notifications
                 (id, task_id, source_key, meeting_no, task_no, expected_date, remaining_days, message, notification_date, is_read)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            )
            .bind(notification_id)
            .bind(task.id)
            .bind(&source_key)
            .bind(&task.meeting_no)
            .bind(task.task_no)
            .bind(&expected_date)
            .bind(remaining_days)
            .bind(&message)
            .bind(&notification_date)
            .bind(if is_read { 1 } else { 0 })
            .execute(&mut *tx)
            .await?;
        }
        // 历史通知也使用主表第一栏的当前序号；同时修正旧版本按任务序号生成的前缀。
        let history_rows = sqlx::query("SELECT id, task_id, message FROM notification_history")
            .fetch_all(&mut *tx)
            .await?;
        for row in history_rows {
            let task_id: i64 = row.try_get("task_id")?;
            let Some(sequence_no) = sequence_by_task_id.get(&task_id) else {
                continue;
            };
            let id: i64 = row.try_get("id")?;
            let old_message: String = row.try_get("message")?;
            let message = with_sequence_prefix(*sequence_no, &old_message);
            if message != old_message {
                sqlx::query("UPDATE notification_history SET message = ?1 WHERE id = ?2")
                    .bind(message)
                    .bind(id)
                    .execute(&mut *tx)
                    .await?;
            }
        }

        sqlx::query("DELETE FROM notification_read_state WHERE notification_date <> ?1")
            .bind(today.format("%Y-%m-%d").to_string())
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "DELETE FROM notification_history WHERE id NOT IN
             (SELECT id FROM notification_history ORDER BY id DESC LIMIT 30)",
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }

    pub async fn list(&self, core_db: &Db) -> Result<Vec<Notification>> {
        self.refresh(core_db).await?;
        let rows = sqlx::query(
            "SELECT id, task_id, meeting_no, task_no, expected_date, remaining_days,
                    message, notification_date, is_read
             FROM notifications ORDER BY remaining_days ASC, id ASC",
        )
        .fetch_all(&self.db)
        .await?;
        Ok(rows.into_iter().map(row_to_notification).collect())
    }

    pub async fn history(
        &self,
        core_db: &Db,
        from: Option<String>,
        to: Option<String>,
    ) -> Result<Vec<Notification>> {
        self.refresh(core_db).await?;
        let mut sql = String::from(
            "SELECT id, task_id, meeting_no, task_no, expected_date, remaining_days,
                    message, notification_date, is_read
             FROM notification_history",
        );
        let mut conditions = Vec::new();
        let mut params = Vec::new();
        if let Some(from) = normalize_history_date(from) {
            conditions.push(format!("notification_date >= ?{}", params.len() + 1));
            params.push(from);
        }
        if let Some(to) = normalize_history_date(to) {
            conditions.push(format!("notification_date <= ?{}", params.len() + 1));
            params.push(to);
        }
        if !conditions.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&conditions.join(" AND "));
        }
        sql.push_str(" ORDER BY notification_date DESC, remaining_days ASC, id DESC");
        let query = params
            .iter()
            .fold(sqlx::query(&sql), |query, value| query.bind(value));
        let rows = query.fetch_all(&self.db).await?;
        Ok(rows.into_iter().map(row_to_notification).collect())
    }

    /// 导入会形成一批全新的计算结果：删除当天已读继承记录并立即重建，
    /// 保证导入后生成的所有通知均为未读，同时保留以前日期的通知历史。
    pub async fn reset_after_import(&self, core_db: &Db) -> Result<()> {
        {
            let _guard = self.refresh_lock.lock().await;
            let notification_date = Local::now().date_naive().format("%Y-%m-%d").to_string();
            let mut tx = self.db.begin().await?;
            sqlx::query("DELETE FROM notifications")
                .execute(&mut *tx)
                .await?;
            sqlx::query("DELETE FROM notification_history WHERE notification_date = ?1")
                .bind(&notification_date)
                .execute(&mut *tx)
                .await?;
            sqlx::query("DELETE FROM notification_read_state WHERE notification_date = ?1")
                .bind(notification_date)
                .execute(&mut *tx)
                .await?;
            tx.commit().await?;
        }
        self.refresh(core_db).await
    }

    pub async fn mark_read(&self, id: i64) -> Result<()> {
        let _guard = self.refresh_lock.lock().await;
        let mut tx = self.db.begin().await?;
        let current = sqlx::query(
            "SELECT task_id, source_key, expected_date, notification_date
             FROM notifications WHERE id = ?1",
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(row) = current {
            let task_id: i64 = row.try_get("task_id")?;
            let source_key: String = row.try_get("source_key")?;
            let expected_date: String = row.try_get("expected_date")?;
            let notification_date: String = row.try_get("notification_date")?;
            sqlx::query("UPDATE notifications SET is_read = 1 WHERE id = ?1")
                .bind(id)
                .execute(&mut *tx)
                .await?;
            sqlx::query(
                "UPDATE notification_history SET is_read = 1
                 WHERE id = ?1 AND source_key = ?2",
            )
            .bind(id)
            .bind(&source_key)
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "UPDATE notification_read_state SET is_read = 1
                 WHERE task_id = ?1 AND source_key = ?2
                   AND expected_date = ?3 AND notification_date = ?4",
            )
            .bind(task_id)
            .bind(source_key)
            .bind(expected_date)
            .bind(notification_date)
            .execute(&mut *tx)
            .await?;
        } else {
            // 历史通知不再存在于当前通知表中，仍可单独标记为已读。
            sqlx::query("UPDATE notification_history SET is_read = 1 WHERE id = ?1")
                .bind(id)
                .execute(&mut *tx)
                .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn mark_all_read(&self) -> Result<()> {
        let _guard = self.refresh_lock.lock().await;
        let notification_date = Local::now().date_naive().format("%Y-%m-%d").to_string();
        let mut tx = self.db.begin().await?;
        sqlx::query("UPDATE notifications SET is_read = 1")
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE notification_history SET is_read = 1 WHERE notification_date = ?1")
            .bind(&notification_date)
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE notification_read_state SET is_read = 1 WHERE notification_date = ?1")
            .bind(notification_date)
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }

}

fn normalize_history_date(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().replace('/', "-"))
        .filter(|value| !value.is_empty())
}

async fn ensure_source_key_column(db: &Pool<Sqlite>, table: &str) -> Result<()> {
    let rows = sqlx::query(&format!("PRAGMA table_info({table})"))
        .fetch_all(db)
        .await?;
    let exists = rows.iter().any(|row| {
        row.try_get::<String, _>("name")
            .is_ok_and(|name| name == "source_key")
    });
    if !exists {
        sqlx::query(&format!(
            "ALTER TABLE {table} ADD COLUMN source_key TEXT NOT NULL DEFAULT ''"
        ))
        .execute(db)
        .await?;
    }
    Ok(())
}

fn notification_source_key(task: &Task) -> String {
    let last_delay = task.delays.last();
    format!(
        "{}|{}|{}|{}|{}|{}|{}|{}|{}",
        task.id,
        task.meeting_no,
        task.task_no,
        task.required_date,
        task.actual_date,
        task.updated_at,
        last_delay.map(|delay| delay.id).unwrap_or_default(),
        last_delay.map(|delay| delay.delay_date.as_str()).unwrap_or(""),
        last_delay.map(|delay| delay.created_at.as_str()).unwrap_or(""),
    )
}

fn row_to_notification(row: sqlx::sqlite::SqliteRow) -> Notification {
    Notification {
        id: row.try_get("id").unwrap_or_default(),
        task_id: row.try_get("task_id").unwrap_or_default(),
        meeting_no: row.try_get("meeting_no").unwrap_or_default(),
        task_no: row.try_get("task_no").unwrap_or_default(),
        expected_date: row.try_get("expected_date").unwrap_or_default(),
        remaining_days: row.try_get("remaining_days").unwrap_or_default(),
        message: row.try_get("message").unwrap_or_default(),
        notification_date: row.try_get("notification_date").unwrap_or_default(),
        is_read: row.try_get::<i64, _>("is_read").unwrap_or(0) != 0,
    }
}

fn sort_tasks_for_sequence(tasks: &mut [Task]) {
    tasks.sort_by(|left, right| {
        compare_meeting_no(&left.meeting_no, &right.meeting_no)
            .then_with(|| left.task_no.cmp(&right.task_no))
            .then_with(|| left.id.cmp(&right.id))
    });
}

fn compare_meeting_no(left: &str, right: &str) -> std::cmp::Ordering {
    match (meeting_no_key(left), meeting_no_key(right)) {
        (Some((left_prefix, left_year, left_number)), Some((right_prefix, right_year, right_number))) => {
            left_prefix
                .cmp(right_prefix)
                .then_with(|| left_year.cmp(&right_year))
                .then_with(|| left_number.cmp(&right_number))
        }
        _ => left.cmp(right),
    }
}

fn meeting_no_key(value: &str) -> Option<(&str, i64, i64)> {
    let (prefix, after_open) = value.trim().split_once('〔')?;
    let (year, after_close) = after_open.split_once('〕')?;
    let number = after_close.strip_suffix('号')?;
    Some((prefix, year.parse().ok()?, number.parse().ok()?))
}

fn with_sequence_prefix(sequence_no: i64, message: &str) -> String {
    let body = strip_sequence_prefix(message);
    format!("序号{}，{}", sequence_no, body)
}

fn strip_sequence_prefix(message: &str) -> &str {
    if let Some(rest) = message.strip_prefix("序号“") {
        if let Some(end) = rest.find("”，") {
            return &rest[end + "”，".len()..];
        }
    }
    if let Some(rest) = message.strip_prefix("序号") {
        if let Some(end) = rest.find('，') {
            let sequence = &rest[..end];
            if !sequence.is_empty()
                && sequence.chars().all(|value| value.is_ascii_digit())
            {
                return &rest[end + '，'.len_utf8()..];
            }
        }
    }
    message
}

fn build_notification(
    task: &Task,
    sequence_no: i64,
    today: NaiveDate,
) -> Option<(String, i64, String)> {
    if !task.actual_date.trim().is_empty() && task.actual_date.trim() != "进行中" {
        return None;
    }
    let expected_date = task
        .delays
        .last()
        .map(|delay| delay.delay_date.trim())
        .filter(|value| !value.is_empty())
        .unwrap_or(task.required_date.trim());
    let expected = NaiveDate::parse_from_str(expected_date, "%Y/%m/%d")
        .or_else(|_| NaiveDate::parse_from_str(expected_date, "%Y-%m-%d"))
        .ok()?;
    let remaining_days = (expected - today).num_days();
    if remaining_days >= 7 {
        return None;
    }
    let body = if remaining_days == 0 {
        format!(
            "第{}中，第{}号任务，已经到达期望完成日期，请检查相关事宜。",
            task.meeting_no, task.task_no
        )
    } else if remaining_days < 0 {
        format!(
            "第{}中，第{}号任务，已经超过期望完成日期{}天。",
            task.meeting_no,
            task.task_no,
            remaining_days.abs()
        )
    } else {
        format!(
            "第{}中，第{}号任务，距期望完成时间{}天。",
            task.meeting_no, task.task_no, remaining_days
        )
    };
    Some((
        expected.to_string(),
        remaining_days,
        with_sequence_prefix(sequence_no, &body),
    ))
}

fn notification_db_path() -> String {
    let exe = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    exe.parent()
        .unwrap_or_else(|| Path::new("."))
        .join("notifications.db")
        .to_string_lossy()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::Delay;

    fn task(actual_date: &str, required_date: &str, delay_date: &str) -> Task {
        Task {
            id: 1,
            meeting_no: "纪要〔2026〕1号".to_string(),
            task_no: 2,
            task_desc: "任务".to_string(),
            dept: String::new(),
            owner: String::new(),
            required_date: required_date.to_string(),
            actual_date: actual_date.to_string(),
            remark: String::new(),
            created_at: String::new(),
            updated_at: String::new(),
            has_attachment: false,
            delays: if delay_date.is_empty() {
                Vec::new()
            } else {
                vec![Delay {
                    id: 1,
                    task_id: 1,
                    meeting_no: "纪要〔2026〕1号".to_string(),
                    task_no: 2,
                    delay_date: delay_date.to_string(),
                    delay_reason: String::new(),
                    created_at: String::new(),
                }]
            },
        }
    }

    #[test]
    fn notification_uses_last_delay_date_and_formats_due_messages() {
        let today = NaiveDate::from_ymd_opt(2026, 9, 2).unwrap();
        let notification = build_notification(
            &task("进行中", "2026/09/20", "2026/09/02"),
            7,
            today,
        )
        .unwrap();
        assert_eq!(notification.0, "2026-09-02");
        assert_eq!(notification.1, 0);
        assert_eq!(
            notification.2,
            "序号7，第纪要〔2026〕1号中，第2号任务，已经到达期望完成日期，请检查相关事宜。"
        );

        let overdue =
            build_notification(&task("进行中", "2026/09/01", ""), 7, today).unwrap();
        assert_eq!(overdue.1, -1);
        assert_eq!(
            overdue.2,
            "序号7，第纪要〔2026〕1号中，第2号任务，已经超过期望完成日期1天。"
        );

        let upcoming =
            build_notification(&task("进行中", "2026/09/07", ""), 7, today).unwrap();
        assert_eq!(upcoming.1, 5);
        assert_eq!(
            upcoming.2,
            "序号7，第纪要〔2026〕1号中，第2号任务，距期望完成时间5天。"
        );
    }

    #[test]
    fn sequence_prefix_replaces_old_task_number_prefix() {
        assert_eq!(
            with_sequence_prefix(7, "序号“2”，原通知正文"),
            "序号7，原通知正文"
        );
        assert_eq!(
            with_sequence_prefix(7, "原通知正文"),
            "序号7，原通知正文"
        );
        assert_eq!(
            with_sequence_prefix(7, "序号2，原通知正文"),
            "序号7，原通知正文"
        );
    }

    #[test]
    fn task_sequence_uses_main_table_meeting_order() {
        let mut tasks = vec![
            Task {
                meeting_no: "纪要〔2026〕10号".to_string(),
                id: 10,
                ..task("进行中", "2026/09/02", "")
            },
            Task {
                meeting_no: "纪要〔2026〕2号".to_string(),
                id: 2,
                ..task("进行中", "2026/09/02", "")
            },
        ];
        sort_tasks_for_sequence(&mut tasks);
        assert_eq!(tasks[0].meeting_no, "纪要〔2026〕2号");
        assert_eq!(tasks[1].meeting_no, "纪要〔2026〕10号");
    }

    #[test]
    fn history_date_filter_accepts_picker_format() {
        assert_eq!(
            normalize_history_date(Some("2026/09/02".to_string())),
            Some("2026-09-02".to_string())
        );
        assert_eq!(normalize_history_date(Some("  ".to_string())), None);
    }

    #[test]
    fn notification_skips_completed_or_far_future_tasks() {
        let today = NaiveDate::from_ymd_opt(2026, 9, 2).unwrap();
        assert!(
            build_notification(&task("2026/09/01", "2026/09/01", ""), 1, today).is_none()
        );
        assert!(build_notification(&task("进行中", "2026/09/09", ""), 1, today).is_none());
    }
    #[tokio::test]
    async fn read_state_changes_only_on_item_click_and_import_resets_to_unread() {
        let unique = uuid::Uuid::new_v4();
        let core_path = std::env::temp_dir().join(format!("hyrwbz_notification_core_{unique}.db"));
        let notification_path =
            std::env::temp_dir().join(format!("hyrwbz_notification_state_{unique}.db"));
        let core_db = crate::db::init(core_path.to_string_lossy().as_ref())
            .await
            .unwrap();
        let expected = (Local::now().date_naive() + chrono::Duration::days(1))
            .format("%Y/%m/%d")
            .to_string();
        sqlx::query(
            "INSERT INTO tasks
             (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark, created_at, updated_at)
             VALUES ('纪要〔2026〕通知测试号', 1, '', '', '', ?1, '进行中', '', 'now', 'v1')",
        )
        .bind(expected)
        .execute(&core_db)
        .await
        .unwrap();
        let store = NotificationStore::open_at(notification_path.to_string_lossy().as_ref())
            .await
            .unwrap();

        store.refresh(&core_db).await.unwrap();
        let notification_id: i64 =
            sqlx::query_scalar("SELECT id FROM notifications LIMIT 1")
                .fetch_one(&store.db)
                .await
                .unwrap();
        let unread: i64 = sqlx::query_scalar("SELECT is_read FROM notifications WHERE id = ?1")
            .bind(notification_id)
            .fetch_one(&store.db)
            .await
            .unwrap();
        assert_eq!(unread, 0);

        let today_text = Local::now().date_naive().format("%Y/%m/%d").to_string();
        let history = store
            .history(&core_db, Some(today_text.clone()), Some(today_text))
            .await
            .unwrap();
        assert_eq!(history.len(), 1);
        let future_text = (Local::now().date_naive() + chrono::Duration::days(1))
            .format("%Y/%m/%d")
            .to_string();
        let future_history = store
            .history(&core_db, Some(future_text), None)
            .await
            .unwrap();
        assert!(future_history.is_empty());

        store.mark_read(notification_id).await.unwrap();
        let history_read: i64 =
            sqlx::query_scalar("SELECT is_read FROM notification_history LIMIT 1")
                .fetch_one(&store.db)
                .await
                .unwrap();
        let persisted_read: i64 =
            sqlx::query_scalar("SELECT is_read FROM notification_read_state LIMIT 1")
                .fetch_one(&store.db)
                .await
                .unwrap();
        assert_eq!(history_read, 1);
        assert_eq!(persisted_read, 1);
        store.refresh(&core_db).await.unwrap();
        let read: i64 = sqlx::query_scalar("SELECT is_read FROM notifications LIMIT 1")
            .fetch_one(&store.db)
            .await
            .unwrap();
        assert_eq!(read, 1);

        sqlx::query("UPDATE tasks SET updated_at = 'v2'")
            .execute(&core_db)
            .await
            .unwrap();
        store.refresh(&core_db).await.unwrap();
        let changed_unread: i64 =
            sqlx::query_scalar("SELECT is_read FROM notifications LIMIT 1")
                .fetch_one(&store.db)
                .await
                .unwrap();
        assert_eq!(changed_unread, 0);

        store.mark_all_read().await.unwrap();
        let all_current_read: i64 =
            sqlx::query_scalar("SELECT MIN(is_read) FROM notifications")
                .fetch_one(&store.db)
                .await
                .unwrap();
        let all_history_read: i64 =
            sqlx::query_scalar("SELECT MIN(is_read) FROM notification_history")
                .fetch_one(&store.db)
                .await
                .unwrap();
        let all_persisted_read: i64 =
            sqlx::query_scalar("SELECT MIN(is_read) FROM notification_read_state")
                .fetch_one(&store.db)
                .await
                .unwrap();
        assert_eq!(all_current_read, 1);
        assert_eq!(all_history_read, 1);
        assert_eq!(all_persisted_read, 1);

        store.reset_after_import(&core_db).await.unwrap();
        let import_unread: i64 =
            sqlx::query_scalar("SELECT is_read FROM notifications LIMIT 1")
                .fetch_one(&store.db)
                .await
                .unwrap();
        assert_eq!(import_unread, 0);

        let historical_id: i64 =
            sqlx::query_scalar("SELECT id FROM notification_history LIMIT 1")
                .fetch_one(&store.db)
                .await
                .unwrap();
        sqlx::query("DELETE FROM notifications")
            .execute(&store.db)
            .await
            .unwrap();
        store.mark_read(historical_id).await.unwrap();
        let historical_read: i64 = sqlx::query_scalar(
            "SELECT is_read FROM notification_history WHERE id = ?1",
        )
        .bind(historical_id)
        .fetch_one(&store.db)
        .await
        .unwrap();
        assert_eq!(historical_read, 1);

        store.db.close().await;
        core_db.close().await;
        std::fs::remove_file(notification_path).ok();
        std::fs::remove_file(core_path).ok();
    }

}
