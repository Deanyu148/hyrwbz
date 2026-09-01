#![allow(unused_assignments)]
use crate::db::Db;
use crate::models::*;
use anyhow::Result;
use axum::{
    extract::{Path, Query, State},
    Json,
};
use chrono::Local;
use serde_json::json;
use sqlx::Row;
use std::collections::HashMap;

type ApiError = (axum::http::StatusCode, String);

fn internal(e: impl std::fmt::Display) -> ApiError {
    (axum::http::StatusCode::INTERNAL_SERVER_ERROR, e.to_string())
}
fn bad(e: impl std::fmt::Display) -> ApiError {
    (axum::http::StatusCode::BAD_REQUEST, e.to_string())
}

pub async fn list_tasks_inner(db: &Db, f: &FilterReq) -> Result<Vec<Task>, ApiError> {
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
    like!("dept", f.dept.as_ref());
    like!("owner", f.owner.as_ref());
    between!("required_date", f.required_date_from, f.required_date_to);
    between!("actual_date", f.actual_date_from, f.actual_date_to);

    let mut sql = String::from("SELECT t.* FROM tasks t");
    if !where_parts.is_empty() {
        sql.push_str(" WHERE ");
        sql.push_str(&where_parts.join(" AND "));
    }
    sql.push_str(" ORDER BY t.meeting_no, t.task_no");

    let q = sqlx::query(&sql);
    let q = params.iter().fold(q, |q, v| q.bind(v));
    let rows = q.fetch_all(db).await.map_err(internal)?;

    // 延期日期筛选（独立二次过滤）
    let mut tasks = build_tasks(rows, db).await?;
    let dd_from = f.delay_date_from.clone();
    let dd_to = f.delay_date_to.clone();
    let di = f.delay_index;
    if dd_from.is_some() || dd_to.is_some() {
        tasks.retain(|t| {
            t.delays.iter().any(|d| {
                let ok = dd_from.as_ref().map_or(true, |a| d.delay_date >= *a)
                    && dd_to.as_ref().map_or(true, |b| d.delay_date <= *b);
                ok
            })
        });
    }
    if let Some(n) = di {
        tasks.retain(|t| t.delays.len() as i64 >= n);
    }
    Ok(tasks)
}

pub async fn list_tasks(State(db): State<Db>, Query(f): Query<FilterReq>) -> Result<Json<Vec<Task>>, ApiError> {
    Ok(Json(list_tasks_inner(&db, &f).await?))
}

async fn build_tasks(rows: Vec<sqlx::sqlite::SqliteRow>, db: &Db) -> Result<Vec<Task>, ApiError> {
    let mut tasks = Vec::new();
    let mut by_id: HashMap<i64, usize> = HashMap::new();
    for r in &rows {
        let id: i64 = r.try_get("id").unwrap_or(0);
        let t = Task {
            id,
            meeting_no: r.try_get::<String, _>("meeting_no").unwrap_or_default(),
            task_no: r.try_get::<i64, _>("task_no").unwrap_or_default(),
            task_desc: r.try_get::<String, _>("task_desc").unwrap_or_default(),
            dept: r.try_get::<String, _>("dept").unwrap_or_default(),
            owner: r.try_get::<String, _>("owner").unwrap_or_default(),
            required_date: r.try_get::<String, _>("required_date").unwrap_or_default(),
            actual_date: r.try_get::<String, _>("actual_date").unwrap_or_default(),
            remark: r.try_get::<String, _>("remark").unwrap_or_default(),
            created_at: r.try_get::<String, _>("created_at").unwrap_or_default(),
            updated_at: r.try_get::<String, _>("updated_at").unwrap_or_default(),
            delays: Vec::new(),
        };
        by_id.insert(id, tasks.len());
        tasks.push(t);
    }
    if !tasks.is_empty() {
        let ids: Vec<String> = tasks.iter().map(|t| t.id.to_string()).collect();
        let sql = format!("SELECT * FROM delays WHERE task_id IN ({}) ORDER BY id", ids.join(","));
        let drows = sqlx::query(&sql).fetch_all(db).await.map_err(internal)?;
        for r in drows {
            let tid: i64 = r.try_get("task_id").unwrap_or(0);
            if let Some(&i) = by_id.get(&tid) {
                tasks[i].delays.push(Delay {
                    id: r.try_get::<i64, _>("id").unwrap_or_default(),
                    task_id: tid,
                    meeting_no: r.try_get::<String, _>("meeting_no").unwrap_or_default(),
                    task_no: r.try_get::<i64, _>("task_no").unwrap_or_default(),
                    delay_date: r.try_get::<String, _>("delay_date").unwrap_or_default(),
                    delay_reason: r.try_get::<String, _>("delay_reason").unwrap_or_default(),
                    created_at: r.try_get::<String, _>("created_at").unwrap_or_default(),
                });
            }
        }
    }
    Ok(tasks)
}

pub async fn create_task(State(db): State<Db>, Json(req): Json<CreateTaskReq>) -> Result<Json<Task>, ApiError> {
    let meeting = req.meeting_no.trim();
    if meeting.is_empty() {
        return Err(bad("meeting_no 不能为空"));
    }
    let max: Option<i64> = sqlx::query_scalar("SELECT MAX(task_no) FROM tasks WHERE meeting_no = ?1")
        .bind(meeting)
        .fetch_optional(&db)
        .await
        .map_err(internal)?;
    let task_no = max.unwrap_or(0) + 1;
    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let res = sqlx::query(
        "INSERT INTO tasks (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)",
    )
    .bind(meeting).bind(task_no).bind(&req.task_desc).bind(&req.dept)
    .bind(&req.owner).bind(&req.required_date).bind(&req.actual_date)
    .bind(&req.remark).bind(&now)
    .execute(&db).await.map_err(internal)?;
    let id = res.last_insert_rowid();
    Ok(Json(Task {
        id, meeting_no: meeting.to_string(), task_no,
        task_desc: req.task_desc, dept: req.dept, owner: req.owner,
        required_date: req.required_date, actual_date: req.actual_date,
        remark: req.remark, created_at: now.clone(), updated_at: now, delays: vec![],
    }))
}

pub async fn update_task(State(db): State<Db>, Path(id): Path<i64>, Json(req): Json<UpdateTaskReq>) -> Result<Json<serde_json::Value>, ApiError> {
    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    sqlx::query(
        "UPDATE tasks SET meeting_no=?1, task_no=?2, task_desc=?3, dept=?4, owner=?5,
         required_date=?6, actual_date=?7, remark=?8, updated_at=?9 WHERE id=?10",
    )
    .bind(&req.meeting_no).bind(req.task_no).bind(&req.task_desc)
    .bind(&req.dept).bind(&req.owner).bind(&req.required_date)
    .bind(&req.actual_date).bind(&req.remark).bind(&now).bind(id)
    .execute(&db).await.map_err(internal)?;
    Ok(Json(json!({"ok": true})))
}

pub async fn delete_task(State(db): State<Db>, Path(id): Path<i64>) -> Result<Json<serde_json::Value>, ApiError> {
    sqlx::query("DELETE FROM delays WHERE task_id = ?1").bind(id).execute(&db).await.map_err(internal)?;
    sqlx::query("DELETE FROM tasks WHERE id = ?1").bind(id).execute(&db).await.map_err(internal)?;
    Ok(Json(json!({"ok": true})))
}

pub async fn list_delays(State(db): State<Db>, Path(id): Path<i64>) -> Result<Json<Vec<Delay>>, ApiError> {
    let rows = sqlx::query("SELECT * FROM delays WHERE task_id = ?1 ORDER BY id").bind(id).fetch_all(&db).await.map_err(internal)?;
    let v: Vec<Delay> = rows.iter().map(|r| Delay {
        id: r.try_get("id").unwrap_or_default(),
        task_id: r.try_get("task_id").unwrap_or_default(),
        meeting_no: r.try_get("meeting_no").unwrap_or_default(),
        task_no: r.try_get("task_no").unwrap_or_default(),
        delay_date: r.try_get("delay_date").unwrap_or_default(),
        delay_reason: r.try_get("delay_reason").unwrap_or_default(),
        created_at: r.try_get("created_at").unwrap_or_default(),
    }).collect();
    Ok(Json(v))
}

pub async fn create_delay(State(db): State<Db>, Path(id): Path<i64>, Json(req): Json<CreateDelayReq>) -> Result<Json<Delay>, ApiError> {
    let row = sqlx::query("SELECT meeting_no, task_no FROM tasks WHERE id = ?1").bind(id).fetch_one(&db).await.map_err(internal)?;
    let meeting_no: String = row.try_get("meeting_no").unwrap_or_default();
    let task_no: i64 = row.try_get("task_no").unwrap_or_default();
    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let res = sqlx::query(
        "INSERT INTO delays (task_id, meeting_no, task_no, delay_date, delay_reason, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
    )
    .bind(id).bind(&meeting_no).bind(task_no).bind(&req.delay_date).bind(&req.delay_reason).bind(&now)
    .execute(&db).await.map_err(internal)?;
    let did = res.last_insert_rowid();
    sqlx::query(
        "DELETE FROM delays WHERE task_id = ?1 AND id NOT IN (SELECT id FROM delays WHERE task_id = ?1 ORDER BY id DESC LIMIT 20)",
    ).bind(id).execute(&db).await.map_err(internal)?;
    Ok(Json(Delay { id: did, task_id: id, meeting_no, task_no, delay_date: req.delay_date, delay_reason: req.delay_reason, created_at: now }))
}

pub async fn delete_delay(State(db): State<Db>, Path(id): Path<i64>) -> Result<Json<serde_json::Value>, ApiError> {
    sqlx::query("DELETE FROM delays WHERE id = ?1").bind(id).execute(&db).await.map_err(internal)?;
    Ok(Json(json!({"ok": true})))
}

pub async fn get_locked(State(db): State<Db>) -> Result<Json<LockedMeeting>, ApiError> {
    let v: Option<String> = sqlx::query_scalar("SELECT value FROM meta WHERE key = 'locked_meeting_no'")
        .fetch_optional(&db).await.map_err(internal)?;
    Ok(Json(LockedMeeting { meeting_no: v.filter(|s| !s.is_empty()) }))
}

pub async fn set_locked(State(db): State<Db>, Json(req): Json<SetLockedMeetingReq>) -> Result<Json<serde_json::Value>, ApiError> {
    let v = req.meeting_no.unwrap_or_default();
    sqlx::query("INSERT INTO meta(key, value) VALUES ('locked_meeting_no', ?1) ON CONFLICT(key) DO UPDATE SET value = ?1")
        .bind(&v).execute(&db).await.map_err(internal)?;
    Ok(Json(json!({"ok": true})))
}

pub async fn list_attachments(State(db): State<Db>, Path(id): Path<i64>) -> Result<Json<Vec<crate::models::Attachment>>, ApiError> {
    let rows = sqlx::query("SELECT * FROM attachments WHERE task_id = ?1 ORDER BY id")
        .bind(id).fetch_all(&db).await.map_err(internal)?;
    let v: Vec<crate::models::Attachment> = rows.iter().map(|r| crate::models::Attachment {
        id: r.try_get("id").unwrap_or_default(),
        task_id: r.try_get("task_id").unwrap_or_default(),
        filename: r.try_get("filename").unwrap_or_default(),
        stored_name: r.try_get("stored_name").unwrap_or_default(),
        created_at: r.try_get("created_at").unwrap_or_default(),
    }).collect();
    Ok(Json(v))
}

pub async fn delete_attachment(State(db): State<Db>, Path(id): Path<i64>) -> Result<Json<serde_json::Value>, ApiError> {
    // 先查 stored_name 删除文件
    let row = sqlx::query("SELECT stored_name FROM attachments WHERE id = ?1").bind(id)
        .fetch_optional(&db).await.map_err(internal)?;
    if let Some(r) = row {
        let stored: String = r.try_get("stored_name").unwrap_or_default();
        let exe = std::env::current_exe().unwrap_or_default();
        let dir = exe.parent().unwrap_or(std::path::Path::new("."));
        let fpath = dir.join("attachments").join(&stored);
        std::fs::remove_file(&fpath).ok();
    }
    sqlx::query("DELETE FROM attachments WHERE id = ?1").bind(id).execute(&db).await.map_err(internal)?;
    Ok(Json(json!({"ok": true})))
}
