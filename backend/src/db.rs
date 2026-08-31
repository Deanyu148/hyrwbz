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
    let base = dirs_or_cwd();
    base.join("data.db").to_string_lossy().to_string()
}

fn dirs_or_cwd() -> std::path::PathBuf {
    if let Some(d) = std::env::var_os("APPDATA") {
        return std::path::PathBuf::from(d).join("hyrwbz");
    }
    if let Ok(h) = std::env::var("HOME") {
        return std::path::PathBuf::from(h).join(".hyrwbz");
    }
    std::path::PathBuf::from(".")
}
