use crate::db::{self, Db};
use anyhow::Result;
use chrono::Local;
use sqlx::Row;
use std::fs;
use std::path::PathBuf;

pub async fn export_db_file() -> Result<String> {
    let src = db::default_db_path();
    let dir = default_export_dir();
    fs::create_dir_all(&dir)?;
    let now = Local::now().format("%Y%m%d_%H%M%S").to_string();
    let dst = dir.join(format!("data_{}.db", now));
    fs::copy(&src, &dst)?;
    Ok(dst.to_string_lossy().to_string())
}

pub async fn import_db_file(src_path: &str) -> Result<()> {
    let dst = db::default_db_path();
    fs::copy(src_path, &dst)?;
    Ok(())
}

pub async fn create_snapshot(db: &Db) -> Result<i64> {
    let tasks = crate::handlers::list_tasks_inner(db, &crate::models::FilterReq::default()).await.map_err(|e| anyhow::anyhow!("{}", e.1))?;
    let payload = serde_json::to_string(&tasks)?;
    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let res = sqlx::query("INSERT INTO snapshots (saved_at, payload) VALUES (?1, ?2)")
        .bind(&now)
        .bind(&payload)
        .execute(db)
        .await?;
    let id = res.last_insert_rowid();
    // 保留 5 份，删除最早的
    sqlx::query(
        "DELETE FROM snapshots WHERE snapshot_id NOT IN (
            SELECT snapshot_id FROM snapshots ORDER BY snapshot_id DESC LIMIT 5
        )",
    )
    .execute(db)
    .await?;
    Ok(id)
}

pub async fn list_snapshots(db: &Db) -> Result<Vec<crate::models::SnapshotInfo>> {
    let rows = sqlx::query("SELECT snapshot_id, saved_at FROM snapshots ORDER BY snapshot_id DESC LIMIT 5")
        .fetch_all(db)
        .await?;
    Ok(rows.iter().map(|r| crate::models::SnapshotInfo {
        snapshot_id: r.try_get("snapshot_id").unwrap_or_default(),
        saved_at: r.try_get("saved_at").unwrap_or_default(),
    }).collect())
}

fn default_export_dir() -> PathBuf {
    if let Some(d) = std::env::var_os("APPDATA") {
        return PathBuf::from(d).join("hyrwbz").join("exports");
    }
    if let Ok(h) = std::env::var("HOME") {
        return PathBuf::from(h).join(".hyrwbz").join("exports");
    }
    PathBuf::from("./exports")
}
