mod db;
mod excel;
mod handlers;
mod import_export;
mod models;

use axum::{
    extract::{Multipart, State},
    http::StatusCode,
    response::IntoResponse,
    routing::{get, post},
    Json, Router,
};
use models::*;
use serde_json::json;
use std::net::SocketAddr;
use tower_http::cors::{Any, CorsLayer};

#[derive(Clone)]
struct AppState {
    db: db::Db,
}

fn app_state(db: db::Db) -> AppState {
    AppState { db }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_env_filter("info").init();
    let db_path = db::default_db_path();
    let db = db::init(&db_path).await?;
    let state = app_state(db);

    let cors = CorsLayer::new().allow_origin(Any).allow_methods(Any).allow_headers(Any);
    let app = Router::new()
        .route("/api/tasks", get(handlers::list_tasks).post(handlers::create_task))
        .route("/api/tasks/{id}", axum::routing::put(handlers::update_task).delete(handlers::delete_task))
        .route("/api/tasks/{id}/delays", get(handlers::list_delays).post(handlers::create_delay))
        .route("/api/delays/{id}", axum::routing::delete(handlers::delete_delay))
        .route("/api/locked-meeting", get(handlers::get_locked).put(handlers::set_locked))
        .route("/api/export/excel", post(handle_export_excel))
        .route("/api/snapshot", post(handle_snapshot))
        .route("/api/snapshots", get(handle_list_snapshots))
        .route("/api/db/export", get(handle_db_export))
        .route("/api/db/import", post(handle_db_import))
        .route("/api/health", get(|| async { "ok" }))
        .layer(cors)
        .with_state(state);

    let port = 7790u16;
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    tracing::info!("listening on http://{}", addr);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn handle_export_excel(State(s): State<AppState>, Json(body): Json<ExportReq>) -> impl IntoResponse {
    let res = excel::export(&s.db, body.filter, body.out_dir).await;
    match res {
        Ok(r) => (StatusCode::OK, Json(json!({"path": r.path, "sheets": r.sheets}))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

#[derive(serde::Deserialize)]
struct ExportReq {
    filter: FilterReq,
    out_dir: Option<String>,
}

async fn handle_snapshot(State(s): State<AppState>) -> impl IntoResponse {
    match import_export::create_snapshot(&s.db).await {
        Ok(id) => (StatusCode::OK, Json(json!({"snapshot_id": id}))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_list_snapshots(State(s): State<AppState>) -> impl IntoResponse {
    match import_export::list_snapshots(&s.db).await {
        Ok(v) => (StatusCode::OK, Json(v)).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_db_export(State(s): State<AppState>) -> impl IntoResponse {
    let _ = s;
    match import_export::export_db_file().await {
        Ok(p) => (StatusCode::OK, Json(json!({"path": p}))).into_response(),
        Err(e) => (StatusCode::INTERNAL_SERVER_ERROR, e.to_string()).into_response(),
    }
}

async fn handle_db_import(State(s): State<AppState>, mut mp: Multipart) -> impl IntoResponse {
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
