// 在 Windows release 模式下使用 GUI 子系统，无控制台窗口
// debug 模式仍用 console 便于看日志；非 Windows 平台此属性被忽略
#![cfg_attr(all(target_os = "windows", not(debug_assertions)), windows_subsystem = "windows")]

mod db;
mod excel;
mod handlers;
mod import_export;
mod models;

use axum::{
    extract::{Multipart, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{delete, get, post, put},
    Json, Router,
};
use models::*;
use serde_json::json;
use std::net::SocketAddr;
use tower_http::cors::{Any, CorsLayer};

/// 解析 --port 参数，默认 7790
fn parse_port() -> u16 {
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        if a == "--port" {
            if let Some(v) = args.next() {
                if let Ok(p) = v.parse::<u16>() {
                    return p;
                }
            }
        }
    }
    7790
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // 仅 debug 模式输出 tracing 日志；release 在 GUI 子系统下也无 stdout
    #[cfg(debug_assertions)]
    tracing_subscriber::fmt().with_env_filter("info").init();

    let port = parse_port();
    let db_path = db::default_db_path();
    let pool = db::init(&db_path).await?;

    let cors = CorsLayer::new().allow_origin(Any).allow_methods(Any).allow_headers(Any);
    let app = Router::new()
        .route("/api/health", get(|| async { "ok" }))
        .route("/api/tasks", get(handlers::list_tasks).post(handlers::create_task))
        .route("/api/tasks/{id}", put(handlers::update_task).delete(handlers::delete_task))
        .route("/api/tasks/{id}/delays", get(handlers::list_delays).post(handlers::create_delay))
        .route("/api/delays/{id}", delete(handlers::delete_delay))
        .route("/api/locked-meeting", get(handlers::get_locked).put(handlers::set_locked))
        .route("/api/export/excel", post(handle_export_excel))
        .route("/api/snapshot", post(handle_snapshot))
        .route("/api/snapshots", get(handle_list_snapshots))
        .route("/api/db/export", get(handle_db_export))
        .route("/api/db/import", post(handle_db_import))
        .layer(cors)
        .with_state(pool);

    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    #[cfg(debug_assertions)]
    tracing::info!("listening on http://{}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn handle_export_excel(State(db): State<db::Db>, Json(body): Json<ExportReq>) -> impl IntoResponse {
    match excel::export(&db, body.filter, body.out_dir).await {
        Ok(r) => (StatusCode::OK, Json(json!({"path": r.path, "sheets": r.sheets}))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

#[derive(serde::Deserialize)]
struct ExportReq {
    filter: FilterReq,
    out_dir: Option<String>,
}

async fn handle_snapshot(State(db): State<db::Db>) -> impl IntoResponse {
    match import_export::create_snapshot(&db).await {
        Ok(id) => (StatusCode::OK, Json(json!({"snapshot_id": id}))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_list_snapshots(State(db): State<db::Db>) -> impl IntoResponse {
    match import_export::list_snapshots(&db).await {
        Ok(v) => (StatusCode::OK, Json(v)).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_db_export(State(_db): State<db::Db>) -> impl IntoResponse {
    match import_export::export_db_file().await {
        Ok(p) => (StatusCode::OK, Json(json!({"path": p}))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_db_import(State(_db): State<db::Db>, mut mp: Multipart) -> impl IntoResponse {
    while let Ok(Some(field)) = mp.next_field().await {
        let name = field.name().unwrap_or("").to_string();
        if name == "file" || name == "db" {
            let data = match field.bytes().await {
                Ok(b) => b,
                Err(e) => return (StatusCode::BAD_REQUEST, e.to_string()).into_response(),
            };
            let tmp = std::env::temp_dir().join(format!("hyrwbz_import_{}.db", uuid::Uuid::new_v4()));
            if let Err(e) = std::fs::write(&tmp, &data) {
                return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response();
            }
            match import_export::import_db_file(tmp.to_string_lossy().as_ref()).await {
                Ok(_) => return (StatusCode::OK, Json(json!({"ok": true}))).into_response(),
                Err(e) => return (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
            }
        }
    }
    (StatusCode::BAD_REQUEST, "no file field".to_string()).into_response()
}
