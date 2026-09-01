use crate::db::Db;
use crate::models::{FilterReq, Task};
use crate::service;
use anyhow::Result;
use chrono::{Local, NaiveDate};
use serde::Serialize;
use sqlx::{Pool, Row, Sqlite};
use std::path::{Path, PathBuf};
use std::str::FromStr;
use std::sync::Arc;
use tokio::sync::Mutex;

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
        if let Some(parent) = Path::new(&path).parent() {
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
        Ok(Self {
            db,
            refresh_lock: Arc::new(Mutex::new(())),
        })
    }

    pub async fn refresh(&self, core_db: &Db) -> Result<()> {
        let _guard = self.refresh_lock.lock().await;
        let today = Local::now().date_naive();
        let tasks = service::list_tasks(core_db, &FilterReq::default())
            .await
            .map_err(|error| anyhow::anyhow!(error.message))?;
        let mut tx = self.db.begin().await?;
        sqlx::query("DELETE FROM notifications")
            .execute(&mut *tx)
            .await?;
        for task in tasks {
            let Some((expected_date, remaining_days, message)) = build_notification(&task, today) else {
                continue;
            };
            let notification_date = today.format("%Y-%m-%d").to_string();
            let old_read: Option<i64> = sqlx::query_scalar(
                "SELECT is_read FROM notification_history
                 WHERE task_id = ?1 AND expected_date = ?2 AND notification_date = ?3",
            )
            .bind(task.id)
            .bind(&expected_date)
            .bind(&notification_date)
            .fetch_optional(&mut *tx)
            .await?;
            let is_read = old_read.unwrap_or(0) != 0;
            sqlx::query(
                "INSERT INTO notification_history
                 (task_id, meeting_no, task_no, expected_date, remaining_days, message, notification_date, is_read)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
                 ON CONFLICT(task_id, expected_date, notification_date) DO UPDATE SET
                   meeting_no = excluded.meeting_no,
                   task_no = excluded.task_no,
                   remaining_days = excluded.remaining_days,
                   message = excluded.message,
                   is_read = excluded.is_read",
            )
            .bind(task.id)
            .bind(&task.meeting_no)
            .bind(task.task_no)
            .bind(&expected_date)
            .bind(remaining_days)
            .bind(&message)
            .bind(&notification_date)
            .bind(if is_read { 1 } else { 0 })
            .execute(&mut *tx)
            .await?;
            sqlx::query(
                "INSERT INTO notifications
                 (task_id, meeting_no, task_no, expected_date, remaining_days, message, notification_date, is_read)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            )
            .bind(task.id)
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

    pub async fn mark_read(&self, id: i64) -> Result<()> {
        let _guard = self.refresh_lock.lock().await;
        let mut tx = self.db.begin().await?;
        let row = sqlx::query(
            "SELECT task_id, expected_date, notification_date FROM notifications WHERE id = ?1",
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(row) = row {
            let task_id: i64 = row.try_get("task_id")?;
            let expected_date: String = row.try_get("expected_date")?;
            let notification_date: String = row.try_get("notification_date")?;
            sqlx::query("UPDATE notifications SET is_read = 1 WHERE id = ?1")
                .bind(id)
                .execute(&mut *tx)
                .await?;
            sqlx::query(
                "UPDATE notification_history SET is_read = 1
                 WHERE task_id = ?1 AND expected_date = ?2 AND notification_date = ?3",
            )
            .bind(task_id)
            .bind(expected_date)
            .bind(notification_date)
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(())
    }

    pub async fn mark_all_read(&self) -> Result<()> {
        let _guard = self.refresh_lock.lock().await;
        let mut tx = self.db.begin().await?;
        sqlx::query("UPDATE notifications SET is_read = 1")
            .execute(&mut *tx)
            .await?;
        sqlx::query("UPDATE notification_history SET is_read = 1 WHERE notification_date = ?1")
            .bind(Local::now().date_naive().format("%Y-%m-%d").to_string())
            .execute(&mut *tx)
            .await?;
        tx.commit().await?;
        Ok(())
    }
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

fn build_notification(task: &Task, today: NaiveDate) -> Option<(String, i64, String)> {
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
    let message = if remaining_days == 0 {
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
    Some((expected.to_string(), remaining_days, message))
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
            today,
        )
        .unwrap();
        assert_eq!(notification.0, "2026-09-02");
        assert_eq!(notification.1, 0);
        assert_eq!(
            notification.2,
            "第纪要〔2026〕1号中，第2号任务，已经到达期望完成日期，请检查相关事宜。"
        );

        let overdue = build_notification(&task("进行中", "2026/09/01", ""), today).unwrap();
        assert_eq!(overdue.1, -1);
        assert_eq!(
            overdue.2,
            "第纪要〔2026〕1号中，第2号任务，已经超过期望完成日期1天。"
        );

        let upcoming = build_notification(&task("进行中", "2026/09/07", ""), today).unwrap();
        assert_eq!(upcoming.1, 5);
        assert_eq!(
            upcoming.2,
            "第纪要〔2026〕1号中，第2号任务，距期望完成时间5天。"
        );
    }

    #[test]
    fn notification_skips_completed_or_far_future_tasks() {
        let today = NaiveDate::from_ymd_opt(2026, 9, 2).unwrap();
        assert!(build_notification(&task("2026/09/01", "2026/09/01", ""), today).is_none());
        assert!(build_notification(&task("进行中", "2026/09/09", ""), today).is_none());
    }
}
