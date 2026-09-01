#![allow(unused_assignments)]

use crate::db::Db;
use crate::models::*;
use chrono::Local;
use serde_json::{json, Value};
use sqlx::Row;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub struct ServiceError {
    pub code: &'static str,
    pub message: String,
}

impl ServiceError {
    pub fn bad(message: impl std::fmt::Display) -> Self {
        Self {
            code: "bad_request",
            message: message.to_string(),
        }
    }

    pub fn internal(message: impl std::fmt::Display) -> Self {
        Self {
            code: "internal",
            message: message.to_string(),
        }
    }
}

impl std::fmt::Display for ServiceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for ServiceError {}

pub type ServiceResult<T> = Result<T, ServiceError>;

fn internal(e: impl std::fmt::Display) -> ServiceError {
    ServiceError::internal(e)
}

fn storage_base() -> PathBuf {
    let exe = std::env::current_exe().unwrap_or_default();
    exe.parent().unwrap_or(Path::new(".")).to_path_buf()
}

pub async fn list_tasks(db: &Db, f: &FilterReq) -> ServiceResult<Vec<Task>> {
    let mut where_parts: Vec<String> = Vec::new();
    let mut params: Vec<String> = Vec::new();
    let mut idx = 1usize;

    macro_rules! like {
        ($field:expr, $val:expr) => {
            if let Some(v) = $val {
                where_parts.push(format!("t.{} LIKE ?{}", $field, idx));
                params.push(format!("%{}%", v));
                idx += 1;
            }
        };
    }
    macro_rules! like_multi {
        ($field:expr, $val:expr) => {
            if let Some(v) = $val {
                let parts: Vec<&str> = v
                    .split(',')
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .collect();
                if !parts.is_empty() {
                    let mut ors = Vec::new();
                    for part in parts {
                        ors.push(format!("t.{} LIKE ?{}", $field, idx));
                        params.push(format!("%{}%", part));
                        idx += 1;
                    }
                    where_parts.push(if ors.len() == 1 {
                        ors.remove(0)
                    } else {
                        format!("({})", ors.join(" OR "))
                    });
                }
            }
        };
    }
    macro_rules! eq_i {
        ($field:expr, $val:expr) => {
            if let Some(v) = $val {
                where_parts.push(format!("t.{} = ?{}", $field, idx));
                params.push(v.to_string());
                idx += 1;
            }
        };
    }
    macro_rules! between {
        ($field:expr, $from:expr, $to:expr) => {
            if let (Some(a), Some(b)) = ($from.as_ref(), $to.as_ref()) {
                where_parts.push(format!("t.{} BETWEEN ?{} AND ?{}", $field, idx, idx + 1));
                params.push(a.clone());
                params.push(b.clone());
                idx += 2;
            } else if let Some(a) = $from.as_ref() {
                where_parts.push(format!("t.{} >= ?{}", $field, idx));
                params.push(a.clone());
                idx += 1;
            } else if let Some(b) = $to.as_ref() {
                where_parts.push(format!("t.{} <= ?{}", $field, idx));
                params.push(b.clone());
                idx += 1;
            }
        };
    }

    like!("meeting_no", f.meeting_no.as_ref());
    eq_i!("task_no", f.task_no);
    like_multi!("dept", f.dept.as_ref());
    like_multi!("owner", f.owner.as_ref());
    between!("required_date", f.required_date_from, f.required_date_to);
    between!("actual_date", f.actual_date_from, f.actual_date_to);
    if let Some(has_attachment) = f.has_attachment {
        where_parts.push(if has_attachment {
            "EXISTS (SELECT 1 FROM attachments a WHERE a.task_id = t.id)".to_string()
        } else {
            "NOT EXISTS (SELECT 1 FROM attachments a WHERE a.task_id = t.id)".to_string()
        });
    }

    let mut sql = String::from(
        "SELECT t.*, EXISTS (SELECT 1 FROM attachments a WHERE a.task_id = t.id) AS has_attachment FROM tasks t",
    );
    if !where_parts.is_empty() {
        sql.push_str(" WHERE ");
        sql.push_str(&where_parts.join(" AND "));
    }
    sql.push_str(" ORDER BY t.meeting_no, t.task_no");

    let query = params
        .iter()
        .fold(sqlx::query(&sql), |query, value| query.bind(value));
    let rows = query.fetch_all(db).await.map_err(internal)?;
    let mut tasks = build_tasks(rows, db).await?;

    let from = f.delay_date_from.as_ref();
    let to = f.delay_date_to.as_ref();
    if from.is_some() || to.is_some() {
        tasks.retain(|task| {
            task.delays.iter().any(|delay| {
                from.map_or(true, |value| delay.delay_date >= *value)
                    && to.map_or(true, |value| delay.delay_date <= *value)
            })
        });
    }
    if let Some(minimum) = f.delay_index {
        tasks.retain(|task| task.delays.len() as i64 >= minimum);
    }
    Ok(tasks)
}

async fn build_tasks(rows: Vec<sqlx::sqlite::SqliteRow>, db: &Db) -> ServiceResult<Vec<Task>> {
    let mut tasks = Vec::new();
    let mut by_id = HashMap::new();
    for row in &rows {
        let id = row.try_get("id").unwrap_or_default();
        by_id.insert(id, tasks.len());
        tasks.push(Task {
            id,
            meeting_no: row.try_get("meeting_no").unwrap_or_default(),
            task_no: row.try_get("task_no").unwrap_or_default(),
            task_desc: row.try_get("task_desc").unwrap_or_default(),
            dept: row.try_get("dept").unwrap_or_default(),
            owner: row.try_get("owner").unwrap_or_default(),
            required_date: row.try_get("required_date").unwrap_or_default(),
            actual_date: row.try_get("actual_date").unwrap_or_default(),
            remark: row.try_get("remark").unwrap_or_default(),
            created_at: row.try_get("created_at").unwrap_or_default(),
            updated_at: row.try_get("updated_at").unwrap_or_default(),
            has_attachment: row.try_get::<i64, _>("has_attachment").unwrap_or(0) != 0,
            delays: Vec::new(),
        });
    }
    if !tasks.is_empty() {
        let ids: Vec<String> = tasks.iter().map(|task| task.id.to_string()).collect();
        let sql = format!(
            "SELECT * FROM delays WHERE task_id IN ({}) ORDER BY id",
            ids.join(",")
        );
        for row in sqlx::query(&sql).fetch_all(db).await.map_err(internal)? {
            let task_id = row.try_get("task_id").unwrap_or_default();
            if let Some(&index) = by_id.get(&task_id) {
                tasks[index].delays.push(Delay {
                    id: row.try_get("id").unwrap_or_default(),
                    task_id,
                    meeting_no: row.try_get("meeting_no").unwrap_or_default(),
                    task_no: row.try_get("task_no").unwrap_or_default(),
                    delay_date: row.try_get("delay_date").unwrap_or_default(),
                    delay_reason: row.try_get("delay_reason").unwrap_or_default(),
                    created_at: row.try_get("created_at").unwrap_or_default(),
                });
            }
        }
    }
    Ok(tasks)
}

pub async fn create_task(db: &Db, req: CreateTaskReq) -> ServiceResult<Task> {
    let meeting = req.meeting_no.trim();
    if meeting.is_empty() {
        return Err(ServiceError::bad("meeting_no 不能为空"));
    }
    let max: Option<i64> =
        sqlx::query_scalar("SELECT MAX(task_no) FROM tasks WHERE meeting_no = ?1")
            .bind(meeting)
            .fetch_optional(db)
            .await
            .map_err(internal)?;
    let task_no = max.unwrap_or(0) + 1;
    let actual_date = if req.actual_date.trim().is_empty() {
        "进行中".to_string()
    } else {
        req.actual_date
    };
    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let result = sqlx::query(
        "INSERT INTO tasks (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark, created_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)",
    ).bind(meeting).bind(task_no).bind(&req.task_desc).bind(&req.dept).bind(&req.owner)
        .bind(&req.required_date).bind(&actual_date).bind(&req.remark).bind(&now)
        .execute(db).await.map_err(internal)?;
    Ok(Task {
        id: result.last_insert_rowid(),
        meeting_no: meeting.to_string(),
        task_no,
        task_desc: req.task_desc,
        dept: req.dept,
        owner: req.owner,
        required_date: req.required_date,
        actual_date,
        remark: req.remark,
        created_at: now.clone(),
        updated_at: now,
        has_attachment: false,
        delays: vec![],
    })
}

pub async fn update_task(db: &Db, id: i64, req: UpdateTaskReq) -> ServiceResult<Value> {
    let actual_date = if req.actual_date.trim().is_empty() {
        "进行中".to_string()
    } else {
        req.actual_date
    };
    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    sqlx::query("UPDATE tasks SET meeting_no=?1, task_no=?2, task_desc=?3, dept=?4, owner=?5, required_date=?6, actual_date=?7, remark=?8, updated_at=?9 WHERE id=?10")
        .bind(&req.meeting_no).bind(req.task_no).bind(&req.task_desc).bind(&req.dept)
        .bind(&req.owner).bind(&req.required_date).bind(&actual_date).bind(&req.remark)
        .bind(&now).bind(id).execute(db).await.map_err(internal)?;
    Ok(json!({"ok": true}))
}

pub async fn delete_task(db: &Db, id: i64) -> ServiceResult<Value> {
    sqlx::query("DELETE FROM delays WHERE task_id = ?1")
        .bind(id)
        .execute(db)
        .await
        .map_err(internal)?;
    sqlx::query("DELETE FROM tasks WHERE id = ?1")
        .bind(id)
        .execute(db)
        .await
        .map_err(internal)?;
    Ok(json!({"ok": true}))
}

pub async fn list_delays(db: &Db, task_id: i64) -> ServiceResult<Vec<Delay>> {
    let rows = sqlx::query("SELECT * FROM delays WHERE task_id = ?1 ORDER BY id")
        .bind(task_id)
        .fetch_all(db)
        .await
        .map_err(internal)?;
    Ok(rows
        .iter()
        .map(|row| Delay {
            id: row.try_get("id").unwrap_or_default(),
            task_id: row.try_get("task_id").unwrap_or_default(),
            meeting_no: row.try_get("meeting_no").unwrap_or_default(),
            task_no: row.try_get("task_no").unwrap_or_default(),
            delay_date: row.try_get("delay_date").unwrap_or_default(),
            delay_reason: row.try_get("delay_reason").unwrap_or_default(),
            created_at: row.try_get("created_at").unwrap_or_default(),
        })
        .collect())
}

pub async fn create_delay(db: &Db, task_id: i64, req: CreateDelayReq) -> ServiceResult<Delay> {
    let row = sqlx::query("SELECT meeting_no, task_no FROM tasks WHERE id = ?1")
        .bind(task_id)
        .fetch_one(db)
        .await
        .map_err(internal)?;
    let meeting_no = row.try_get("meeting_no").unwrap_or_default();
    let task_no = row.try_get("task_no").unwrap_or_default();
    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let result = sqlx::query("INSERT INTO delays (task_id, meeting_no, task_no, delay_date, delay_reason, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)")
        .bind(task_id).bind(&meeting_no).bind(task_no).bind(&req.delay_date).bind(&req.delay_reason).bind(&now)
        .execute(db).await.map_err(internal)?;
    sqlx::query("DELETE FROM delays WHERE task_id = ?1 AND id NOT IN (SELECT id FROM delays WHERE task_id = ?1 ORDER BY id DESC LIMIT 20)")
        .bind(task_id).execute(db).await.map_err(internal)?;
    Ok(Delay {
        id: result.last_insert_rowid(),
        task_id,
        meeting_no,
        task_no,
        delay_date: req.delay_date,
        delay_reason: req.delay_reason,
        created_at: now,
    })
}

pub async fn delete_delay(db: &Db, id: i64) -> ServiceResult<Value> {
    sqlx::query("DELETE FROM delays WHERE id = ?1")
        .bind(id)
        .execute(db)
        .await
        .map_err(internal)?;
    Ok(json!({"ok": true}))
}

pub async fn get_locked(db: &Db) -> ServiceResult<LockedMeeting> {
    let value: Option<String> =
        sqlx::query_scalar("SELECT value FROM meta WHERE key = 'locked_meeting_no'")
            .fetch_optional(db)
            .await
            .map_err(internal)?;
    Ok(LockedMeeting {
        meeting_no: value.filter(|value| !value.is_empty()),
    })
}

pub async fn set_locked(db: &Db, req: SetLockedMeetingReq) -> ServiceResult<Value> {
    let value = req.meeting_no.unwrap_or_default();
    sqlx::query("INSERT INTO meta(key, value) VALUES ('locked_meeting_no', ?1) ON CONFLICT(key) DO UPDATE SET value = ?1")
        .bind(&value).execute(db).await.map_err(internal)?;
    Ok(json!({"ok": true}))
}

pub async fn list_attachments(db: &Db, task_id: i64) -> ServiceResult<Vec<Attachment>> {
    let rows = sqlx::query("SELECT * FROM attachments WHERE task_id = ?1 ORDER BY id")
        .bind(task_id)
        .fetch_all(db)
        .await
        .map_err(internal)?;
    Ok(rows
        .iter()
        .map(|row| Attachment {
            id: row.try_get("id").unwrap_or_default(),
            task_id: row.try_get("task_id").unwrap_or_default(),
            filename: row.try_get("filename").unwrap_or_default(),
            stored_name: row.try_get("stored_name").unwrap_or_default(),
            created_at: row.try_get("created_at").unwrap_or_default(),
        })
        .collect())
}

pub async fn delete_attachment(db: &Db, id: i64) -> ServiceResult<Value> {
    if let Some(row) = sqlx::query("SELECT stored_name FROM attachments WHERE id = ?1")
        .bind(id)
        .fetch_optional(db)
        .await
        .map_err(internal)?
    {
        let stored: String = row.try_get("stored_name").unwrap_or_default();
        remove_attachment_file(&attachment_path(&stored))?;
    }
    sqlx::query("DELETE FROM attachments WHERE id = ?1")
        .bind(id)
        .execute(db)
        .await
        .map_err(internal)?;
    Ok(json!({"ok": true}))
}

fn sanitize_dir_name(value: &str) -> String {
    value.replace(['/', '\\', ':', '*', '?', '"', '<', '>', '|'], "_")
}

fn attachment_path(stored_name: &str) -> PathBuf {
    storage_base().join("attachments").join(stored_name)
}

fn build_stored_name(meeting_no: &str, task_no: i64, filename: &str) -> String {
    format!(
        "{}/{}/{}_{}",
        sanitize_dir_name(meeting_no),
        task_no,
        uuid::Uuid::new_v4(),
        sanitize_dir_name(filename)
    )
}

fn write_attachment(path: &Path, data: &[u8]) -> ServiceResult<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(internal)?;
    }
    std::fs::write(path, data).map_err(internal)
}

fn remove_attachment_file(path: &Path) -> ServiceResult<()> {
    match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(internal(error)),
    }
}

pub async fn upload_attachment(
    db: &Db,
    task_id: i64,
    filename: String,
    data: &[u8],
) -> ServiceResult<Attachment> {
    if filename.trim().is_empty() {
        return Err(ServiceError::bad("filename 不能为空"));
    }
    let row = sqlx::query("SELECT meeting_no, task_no FROM tasks WHERE id = ?1")
        .bind(task_id)
        .fetch_one(db)
        .await
        .map_err(internal)?;
    let meeting_no: String = row.try_get("meeting_no").unwrap_or_default();
    let task_no: i64 = row.try_get("task_no").unwrap_or_default();
    let stored_name = build_stored_name(&meeting_no, task_no, &filename);
    let file_path = attachment_path(&stored_name);
    write_attachment(&file_path, data)?;

    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let result = sqlx::query("INSERT INTO attachments (task_id, filename, stored_name, created_at) VALUES (?1, ?2, ?3, ?4)")
        .bind(task_id)
        .bind(&filename)
        .bind(&stored_name)
        .bind(&now)
        .execute(db)
        .await;
    let result = match result {
        Ok(result) => result,
        Err(error) => {
            remove_attachment_file(&file_path).ok();
            return Err(internal(error));
        }
    };
    Ok(Attachment {
        id: result.last_insert_rowid(),
        task_id,
        filename,
        stored_name,
        created_at: now,
    })
}

pub async fn update_attachment(
    db: &Db,
    id: i64,
    filename: String,
    data: &[u8],
) -> ServiceResult<Attachment> {
    if filename.trim().is_empty() {
        return Err(ServiceError::bad("filename 不能为空"));
    }
    let row = sqlx::query(
        "SELECT a.task_id, a.stored_name, t.meeting_no, t.task_no
         FROM attachments a JOIN tasks t ON t.id = a.task_id WHERE a.id = ?1",
    )
    .bind(id)
    .fetch_one(db)
    .await
    .map_err(internal)?;
    let task_id: i64 = row.try_get("task_id").unwrap_or_default();
    let old_stored_name: String = row.try_get("stored_name").unwrap_or_default();
    let meeting_no: String = row.try_get("meeting_no").unwrap_or_default();
    let task_no: i64 = row.try_get("task_no").unwrap_or_default();
    let stored_name = build_stored_name(&meeting_no, task_no, &filename);
    let file_path = attachment_path(&stored_name);
    write_attachment(&file_path, data)?;

    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let result = sqlx::query(
        "UPDATE attachments SET filename = ?1, stored_name = ?2, created_at = ?3 WHERE id = ?4",
    )
    .bind(&filename)
    .bind(&stored_name)
    .bind(&now)
    .bind(id)
    .execute(db)
    .await;
    if let Err(error) = result {
        remove_attachment_file(&file_path).ok();
        return Err(internal(error));
    }

    remove_attachment_file(&attachment_path(&old_stored_name)).ok();
    Ok(Attachment {
        id,
        task_id,
        filename,
        stored_name,
        created_at: now,
    })
}

pub async fn download_attachment(db: &Db, id: i64) -> ServiceResult<(String, Vec<u8>)> {
    let row = sqlx::query("SELECT filename, stored_name FROM attachments WHERE id = ?1")
        .bind(id)
        .fetch_one(db)
        .await
        .map_err(internal)?;
    let filename: String = row.try_get("filename").unwrap_or_default();
    let stored_name: String = row.try_get("stored_name").unwrap_or_default();
    let bytes = std::fs::read(attachment_path(&stored_name)).map_err(internal)?;
    Ok((filename, bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn attachment_file_can_be_written_and_removed() {
        let path = std::env::temp_dir().join(format!(
            "hyrwbz_attachment_test_{}",
            uuid::Uuid::new_v4()
        ));
        write_attachment(&path, b"attachment").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"attachment");
        remove_attachment_file(&path).unwrap();
        assert!(!path.exists());
    }
}
