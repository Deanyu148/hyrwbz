use anyhow::Result;
use sqlx::sqlite::{
    SqliteConnectOptions, SqliteJournalMode, SqlitePoolOptions, SqliteSynchronous,
};
use sqlx::{Pool, Sqlite};
use std::str::FromStr;
use std::time::Duration;
include!(concat!(env!("OUT_DIR"), "/migrations.rs"));

pub type Db = Pool<Sqlite>;

pub async fn init(db_path: &str) -> Result<Db> {
    if let Some(parent) = std::path::Path::new(db_path).parent() {
        std::fs::create_dir_all(parent).ok();
    }
    let options = SqliteConnectOptions::from_str(&format!("sqlite://{}", db_path))?
        .create_if_missing(true)
        .foreign_keys(true)
        .journal_mode(SqliteJournalMode::Wal)
        .synchronous(SqliteSynchronous::Normal)
        .busy_timeout(Duration::from_secs(10))
        .pragma("temp_store", "MEMORY")
        .pragma("cache_size", "-20000");
    let pool = SqlitePoolOptions::new()
        .min_connections(1)
        .max_connections(6)
        .idle_timeout(Some(Duration::from_secs(300)))
        .connect_with(options)
        .await?;
    for sql in MIGRATIONS.iter() {
        sqlx::query(sql).execute(&pool).await?;
    }
    // 旧版本允许未完成任务的实际完成时间为空；统一迁移为明确的进行中状态。
    sqlx::query("UPDATE tasks SET actual_date = '进行中' WHERE trim(actual_date) = ''")
        .execute(&pool)
        .await?;
    // 让 SQLite 根据当前数据分布更新查询规划统计信息。
    sqlx::query("PRAGMA optimize").execute(&pool).await?;
    Ok(pool)
}

pub fn default_db_path() -> String {
    // 数据库放在 exe 同目录下（安装目录），不再用 APPDATA
    let exe = std::env::current_exe().unwrap_or_else(|_| std::path::PathBuf::from("."));
    let dir = exe.parent().unwrap_or_else(|| std::path::Path::new("."));
    dir.join("data.db").to_string_lossy().to_string()
}
