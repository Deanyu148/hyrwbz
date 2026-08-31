use anyhow::Result;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::{Pool, Sqlite};
use std::str::FromStr;
include!(concat!(env!("OUT_DIR"), "/migrations.rs"));

pub type Db = Pool<Sqlite>;

pub async fn init(db_path: &str) -> Result<Db> {
    if let Some(parent) = std::path::Path::new(db_path).parent() {
        std::fs::create_dir_all(parent).ok();
    }
    let options = SqliteConnectOptions::from_str(&format!("sqlite://{}", db_path))?
        .create_if_missing(true)
        .foreign_keys(true);
    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(options)
        .await?;
    for sql in MIGRATIONS.iter() {
        sqlx::query(sql).execute(&pool).await?;
    }
    Ok(pool)
}

pub fn default_db_path() -> String {
    // 数据库放在 exe 同目录下（安装目录），不再用 APPDATA
    let exe = std::env::current_exe().unwrap_or_else(|_| std::path::PathBuf::from("."));
    let dir = exe.parent().unwrap_or_else(|| std::path::Path::new("."));
    dir.join("data.db").to_string_lossy().to_string()
}
