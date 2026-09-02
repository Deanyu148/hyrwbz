use crate::db::Db;
use crate::models::{
    CreateDelayReq, CreateSnapshotReq, FilterReq, SetLockedMeetingReq, UpdateTaskReq,
};
use crate::{excel, import_export, notifications, search_index, service};
use interprocess::local_socket::tokio::Stream;
use interprocess::local_socket::traits::tokio::Listener as _;
use interprocess::local_socket::{GenericFilePath, ListenerOptions, ToFsName};
use serde::de::DeserializeOwned;
use serde::Deserialize;
use serde_json::{json, Value};
use std::sync::Arc;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::sync::Mutex;

const MAGIC: &[u8; 4] = b"HYRW";
const VERSION: u16 = 1;
const FLAG_RESPONSE: u16 = 1;
const FLAG_ERROR: u16 = 2;
const HEADER_SIZE: usize = 20;
const MAX_JSON: u32 = 1024 * 1024;
const MAX_BINARY: u64 = 512 * 1024 * 1024;

#[derive(Debug)]
struct Frame {
    flags: u16,
    header: Value,
    binary: Vec<u8>,
}

#[derive(Debug, Deserialize)]
struct RequestHeader {
    id: u64,
    method: String,
    #[serde(default)]
    params: Value,
}

#[derive(Debug, Deserialize)]
struct IdParam {
    id: i64,
}
#[derive(Debug, Deserialize)]
struct TaskIdParam {
    task_id: i64,
}
#[derive(Debug, Deserialize)]
struct UpdateTaskParam {
    id: i64,
    task: UpdateTaskReq,
}
#[derive(Debug, Deserialize)]
struct CreateDelayParam {
    task_id: i64,
    delay: CreateDelayReq,
}
#[derive(Debug, Deserialize)]
struct ExportParam {
    #[serde(default)]
    filter: FilterReq,
    out_dir: Option<String>,
}
#[derive(Debug, Deserialize)]
struct ImportParam {
    filename: String,
    #[serde(default)]
    move_remark_to_delay_reason: bool,
}
#[derive(Debug, Deserialize)]
struct UploadParam {
    task_id: i64,
    filename: String,
}
#[derive(Debug, Deserialize)]
struct UpdateAttachmentParam {
    id: i64,
    filename: String,
}
#[derive(Debug, Deserialize)]
struct NotificationHistoryParam {
    from: Option<String>,
    to: Option<String>,
}
#[derive(Debug, Deserialize)]
struct SearchParam {
    query: String,
}

pub async fn serve(
    socket_path: &str,
    db: Db,
    notification_store: notifications::NotificationStore,
    search_index: search_index::SearchIndex,
) -> anyhow::Result<()> {
    let name = socket_path.to_fs_name::<GenericFilePath>()?;
    let listener = ListenerOptions::new().name(name).create_tokio()?;
    loop {
        let stream = listener.accept().await?;
        let db = db.clone();
        let notification_store = notification_store.clone();
        let search_index = search_index.clone();
        tokio::spawn(async move {
            if let Err(_error) =
                handle_connection(stream, db, notification_store, search_index).await
            {
                #[cfg(debug_assertions)]
                tracing::warn!("local RPC connection closed: {}", _error);
            }
        });
    }
}

async fn handle_connection(
    stream: Stream,
    db: Db,
    notification_store: notifications::NotificationStore,
    search_index: search_index::SearchIndex,
) -> anyhow::Result<()> {
    let (mut reader, writer) = tokio::io::split(stream);
    let writer = Arc::new(Mutex::new(writer));
    loop {
        let frame = match read_frame(&mut reader).await {
            Ok(frame) => frame,
            Err(error) if error.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(()),
            Err(error) => return Err(error.into()),
        };
        let db = db.clone();
        let notification_store = notification_store.clone();
        let search_index = search_index.clone();
        let writer = Arc::clone(&writer);
        tokio::spawn(async move {
            let response = match serde_json::from_value::<RequestHeader>(frame.header) {
                Ok(request) => {
                    dispatch_with_notifications(
                        &db,
                        &notification_store,
                        &search_index,
                        request,
                        frame.binary,
                    )
                    .await
                }
                Err(error) => {
                    error_frame(0, "protocol", format!("invalid request header: {error}"))
                }
            };
            let mut writer = writer.lock().await;
            if let Err(_error) = write_frame(&mut *writer, &response).await {
                #[cfg(debug_assertions)]
                tracing::warn!("local RPC response write failed: {}", _error);
            }
        });
    }
}

#[cfg(test)]
async fn dispatch(db: &Db, request: RequestHeader, binary: Vec<u8>) -> Frame {
    dispatch_inner(db, None, None, request, binary).await
}

async fn dispatch_with_notifications(
    db: &Db,
    notification_store: &notifications::NotificationStore,
    search_index: &search_index::SearchIndex,
    request: RequestHeader,
    binary: Vec<u8>,
) -> Frame {
    dispatch_inner(
        db,
        Some(notification_store),
        Some(search_index),
        request,
        binary,
    )
    .await
}

async fn dispatch_inner(
    db: &Db,
    notification_store: Option<&notifications::NotificationStore>,
    search_index: Option<&search_index::SearchIndex>,
    request: RequestHeader,
    binary: Vec<u8>,
) -> Frame {
    let id = request.id;
    let method = request.method.clone();
    let result: Result<(Value, Vec<u8>), service::ServiceError> = async {
        let value = match request.method.as_str() {
            "system.health" => json!({"ok": true, "protocol": VERSION}),
            "task.list" => serde_json::to_value(service::list_tasks(db, &decode(request.params)?).await?).map_err(service::ServiceError::internal)?,
            "search.tasks" => {
                let index = search_index.ok_or_else(|| service::ServiceError::internal("search index unavailable"))?;
                let param: SearchParam = decode(request.params)?;
                serde_json::to_value(index.search_task_ids(db, &param.query).await.map_err(service::ServiceError::internal)?)
                    .map_err(service::ServiceError::internal)?
            }
            "task.create" => serde_json::to_value(service::create_task(db, decode(request.params)?).await?).map_err(service::ServiceError::internal)?,
            "task.update" => {
                let param: UpdateTaskParam = decode(request.params)?;
                service::update_task(db, param.id, param.task).await?
            }
            "task.delete" => service::delete_task(db, decode::<IdParam>(request.params)?.id).await?,
            "delay.list" => serde_json::to_value(service::list_delays(db, decode::<TaskIdParam>(request.params)?.task_id).await?).map_err(service::ServiceError::internal)?,
            "delay.create" => {
                let param: CreateDelayParam = decode(request.params)?;
                serde_json::to_value(service::create_delay(db, param.task_id, param.delay).await?).map_err(service::ServiceError::internal)?
            }
            "delay.delete" => service::delete_delay(db, decode::<IdParam>(request.params)?.id).await?,
            "meeting_lock.get" => serde_json::to_value(service::get_locked(db).await?).map_err(service::ServiceError::internal)?,
            "meeting_lock.set" => service::set_locked(db, decode::<SetLockedMeetingReq>(request.params)?).await?,
            "notification.list" => {
                let store = notification_store.ok_or_else(|| service::ServiceError::internal("notification service unavailable"))?;
                serde_json::to_value(store.list(db).await.map_err(service::ServiceError::internal)?).map_err(service::ServiceError::internal)?
            }
            "notification.history" => {
                let store = notification_store.ok_or_else(|| service::ServiceError::internal("notification service unavailable"))?;
                let param: NotificationHistoryParam = decode(request.params)?;
                serde_json::to_value(store.history(db, param.from, param.to).await.map_err(service::ServiceError::internal)?).map_err(service::ServiceError::internal)?
            }
            "notification.mark_read" => {
                let store = notification_store.ok_or_else(|| service::ServiceError::internal("notification service unavailable"))?;
                store.mark_read(decode::<IdParam>(request.params)?.id).await.map_err(service::ServiceError::internal)?;
                json!({"ok": true})
            }
            "notification.mark_all_read" => {
                let store = notification_store.ok_or_else(|| service::ServiceError::internal("notification service unavailable"))?;
                store.mark_all_read().await.map_err(service::ServiceError::internal)?;
                json!({"ok": true})
            }
            "snapshot.create" => {
                let param: CreateSnapshotReq = decode(request.params)?;
                serde_json::to_value(
                    import_export::create_snapshot(db, param.remark)
                        .await
                        .map_err(service::ServiceError::internal)?,
                )
                .map_err(service::ServiceError::internal)?
            }
            "snapshot.list" => serde_json::to_value(import_export::list_snapshots(db).await.map_err(service::ServiceError::internal)?).map_err(service::ServiceError::internal)?,
            "snapshot.get" => serde_json::to_value(
                import_export::get_snapshot(db, decode::<IdParam>(request.params)?.id)
                    .await
                    .map_err(service::ServiceError::internal)?,
            )
            .map_err(service::ServiceError::internal)?,
            "export.excel" => {
                let param: ExportParam = decode(request.params)?;
                serde_json::to_value(excel::export(db, param.filter, param.out_dir).await.map_err(service::ServiceError::internal)?).map_err(service::ServiceError::internal)?
            }
            "export.csv" => {
                let param: ExportParam = decode(request.params)?;
                json!({"path": import_export::export_csv(db, param.filter, param.out_dir).await.map_err(service::ServiceError::internal)?})
            }
            "export.database" => json!({"path": import_export::export_db_file().await.map_err(service::ServiceError::internal)?}),
            "export.all_files" => {
                let param: ExportParam = decode(request.params)?;
                json!({"path": import_export::export_all_files(db, param.out_dir).await.map_err(service::ServiceError::internal)?})
            }
            "import.excel" => {
                let param: ImportParam = decode(request.params)?;
                let ext = excel_extension(&param.filename, &binary);
                let path = write_temp("excel", ext, &binary)?;
                let result = import_export::import_excel(
                    db,
                    path.to_string_lossy().as_ref(),
                    param.move_remark_to_delay_reason,
                )
                .await
                .map_err(service::ServiceError::internal);
                std::fs::remove_file(&path).ok();
                let result = result?;
                reset_notifications_after_import(notification_store, db).await?;
                serde_json::to_value(result).map_err(service::ServiceError::internal)?
            }
            "import.csv" => {
                let param: ImportParam = decode(request.params)?;
                let path = write_temp("csv", "csv", &binary)?;
                let result = import_export::import_csv(
                    db,
                    path.to_string_lossy().as_ref(),
                    param.move_remark_to_delay_reason,
                )
                .await
                .map_err(service::ServiceError::internal);
                std::fs::remove_file(&path).ok();
                let result = result?;
                reset_notifications_after_import(notification_store, db).await?;
                serde_json::to_value(result).map_err(service::ServiceError::internal)?
            }
            "import.database" => {
                let _: ImportParam = decode(request.params)?;
                let path = write_temp("database", "db", &binary)?;
                let result = import_export::import_db_file(db, path.to_string_lossy().as_ref()).await.map_err(service::ServiceError::internal);
                std::fs::remove_file(&path).ok();
                result?;
                reset_notifications_after_import(notification_store, db).await?;
                json!({"ok": true})
            }
            "import.all_files" => {
                let _: ImportParam = decode(request.params)?;
                let path = write_temp("all_files", "zip", &binary)?;
                let result = import_export::import_all_files(db, path.to_string_lossy().as_ref()).await.map_err(service::ServiceError::internal);
                std::fs::remove_file(&path).ok();
                result?;
                reset_notifications_after_import(notification_store, db).await?;
                json!({"ok": true})
            }
            "attachment.list" => serde_json::to_value(service::list_attachments(db, decode::<TaskIdParam>(request.params)?.task_id).await?).map_err(service::ServiceError::internal)?,
            "attachment.upload" => {
                let param: UploadParam = decode(request.params)?;
                serde_json::to_value(service::upload_attachment(db, param.task_id, param.filename, &binary).await?).map_err(service::ServiceError::internal)?
            }
            "attachment.update" => {
                let param: UpdateAttachmentParam = decode(request.params)?;
                serde_json::to_value(service::update_attachment(db, param.id, param.filename, &binary).await?).map_err(service::ServiceError::internal)?
            }
            "attachment.delete" => service::delete_attachment(db, decode::<IdParam>(request.params)?.id).await?,
            "attachment.download" => {
                let (filename, bytes) = service::download_attachment(db, decode::<IdParam>(request.params)?.id).await?;
                return Ok((json!({"filename": filename}), bytes));
            }
            _ => return Err(service::ServiceError { code: "method_not_found", message: format!("unknown RPC method: {}", request.method) }),
        };
        Ok((value, Vec::new()))
    }.await;

    if result.is_ok() {
        if method_invalidates_search(&method) {
            if let Some(index) = search_index {
                index.invalidate();
            }
        }
        if method_invalidates_notifications(&method) {
            if let Some(store) = notification_store {
                store.invalidate().await;
            }
        }
    }
    match result {
        Ok((value, payload)) => success_frame(id, value, payload),
        Err(error) => error_frame(id, error.code, error.message),
    }
}

fn method_invalidates_search(method: &str) -> bool {
    matches!(
        method,
        "task.create"
            | "task.update"
            | "task.delete"
            | "delay.create"
            | "delay.delete"
            | "attachment.upload"
            | "attachment.delete"
            | "import.excel"
            | "import.csv"
            | "import.database"
            | "import.all_files"
    )
}

fn method_invalidates_notifications(method: &str) -> bool {
    matches!(
        method,
        "task.create" | "task.update" | "task.delete" | "delay.create" | "delay.delete"
    )
}

async fn reset_notifications_after_import(
    notification_store: Option<&notifications::NotificationStore>,
    db: &Db,
) -> Result<(), service::ServiceError> {
    if let Some(store) = notification_store {
        store
            .reset_after_import(db)
            .await
            .map_err(service::ServiceError::internal)?;
    }
    Ok(())
}

fn decode<T: DeserializeOwned>(value: Value) -> Result<T, service::ServiceError> {
    serde_json::from_value(value)
        .map_err(|error| service::ServiceError::bad(format!("invalid params: {error}")))
}

fn write_temp(
    prefix: &str,
    extension: &str,
    bytes: &[u8],
) -> Result<std::path::PathBuf, service::ServiceError> {
    let path = std::env::temp_dir().join(format!(
        "hyrwbz_{}_{}.{}",
        prefix,
        uuid::Uuid::new_v4(),
        extension
    ));
    std::fs::write(&path, bytes).map_err(service::ServiceError::internal)?;
    Ok(path)
}

fn excel_extension(filename: &str, bytes: &[u8]) -> &'static str {
    let head = &bytes[..bytes.len().min(8)];
    if head.starts_with(&[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]) {
        "xls"
    } else if head.starts_with(&[0x50, 0x4B]) {
        "xlsx"
    } else if std::path::Path::new(filename)
        .extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| value.eq_ignore_ascii_case("xls"))
    {
        "xls"
    } else {
        "xlsx"
    }
}

fn success_frame(id: u64, result: Value, binary: Vec<u8>) -> Frame {
    Frame {
        flags: FLAG_RESPONSE,
        header: json!({"id": id, "result": result}),
        binary,
    }
}

fn error_frame(id: u64, code: impl Into<String>, message: impl Into<String>) -> Frame {
    Frame {
        flags: FLAG_RESPONSE | FLAG_ERROR,
        header: json!({"id": id, "error": {"code": code.into(), "message": message.into()}}),
        binary: Vec::new(),
    }
}

async fn read_frame<R: AsyncRead + Unpin>(reader: &mut R) -> std::io::Result<Frame> {
    let mut prefix = [0u8; HEADER_SIZE];
    reader.read_exact(&mut prefix).await?;
    if &prefix[..4] != MAGIC {
        return Err(invalid_data("invalid RPC magic"));
    }
    let version = u16::from_be_bytes([prefix[4], prefix[5]]);
    if version != VERSION {
        return Err(invalid_data("unsupported RPC version"));
    }
    let flags = u16::from_be_bytes([prefix[6], prefix[7]]);
    let json_len = u32::from_be_bytes(prefix[8..12].try_into().unwrap());
    let binary_len = u64::from_be_bytes(prefix[12..20].try_into().unwrap());
    if json_len > MAX_JSON || binary_len > MAX_BINARY {
        return Err(invalid_data("RPC frame too large"));
    }
    let mut json_bytes = vec![0u8; json_len as usize];
    reader.read_exact(&mut json_bytes).await?;
    let header =
        serde_json::from_slice(&json_bytes).map_err(|error| invalid_data(error.to_string()))?;
    let mut binary = vec![0u8; binary_len as usize];
    reader.read_exact(&mut binary).await?;
    Ok(Frame {
        flags,
        header,
        binary,
    })
}

async fn write_frame<W: AsyncWrite + Unpin>(writer: &mut W, frame: &Frame) -> std::io::Result<()> {
    let json_bytes =
        serde_json::to_vec(&frame.header).map_err(|error| invalid_data(error.to_string()))?;
    if json_bytes.len() > MAX_JSON as usize || frame.binary.len() as u64 > MAX_BINARY {
        return Err(invalid_data("RPC frame too large"));
    }
    let mut prefix = [0u8; HEADER_SIZE];
    prefix[..4].copy_from_slice(MAGIC);
    prefix[4..6].copy_from_slice(&VERSION.to_be_bytes());
    prefix[6..8].copy_from_slice(&frame.flags.to_be_bytes());
    prefix[8..12].copy_from_slice(&(json_bytes.len() as u32).to_be_bytes());
    prefix[12..20].copy_from_slice(&(frame.binary.len() as u64).to_be_bytes());
    writer.write_all(&prefix).await?;
    writer.write_all(&json_bytes).await?;
    writer.write_all(&frame.binary).await?;
    writer.flush().await
}

fn invalid_data(message: impl Into<String>) -> std::io::Error {
    std::io::Error::new(std::io::ErrorKind::InvalidData, message.into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn frame_round_trip_preserves_binary() {
        let frame = success_frame(7, json!({"value": "ok"}), vec![0, 1, 2, 255]);
        let mut bytes = Vec::new();
        write_frame(&mut bytes, &frame).await.unwrap();
        let mut cursor = std::io::Cursor::new(bytes);
        let decoded = read_frame(&mut cursor).await.unwrap();
        assert_eq!(decoded.flags, FLAG_RESPONSE);
        assert_eq!(decoded.header["id"], 7);
        assert_eq!(decoded.binary, vec![0, 1, 2, 255]);
    }

    #[tokio::test]
    async fn rejects_invalid_magic() {
        let mut bytes = vec![0u8; HEADER_SIZE];
        bytes[4..6].copy_from_slice(&VERSION.to_be_bytes());
        let error = read_frame(&mut std::io::Cursor::new(bytes))
            .await
            .unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::InvalidData);
    }

    #[tokio::test]
    async fn rpc_dispatch_handles_crud_and_binary_without_base64() {
        let unique = uuid::Uuid::new_v4();
        let db_path = std::env::temp_dir().join(format!("hyrwbz_rpc_test_{unique}.db"));
        let db = crate::db::init(db_path.to_string_lossy().as_ref())
            .await
            .unwrap();

        let created = dispatch(
            &db,
            RequestHeader {
                id: 1,
                method: "task.create".to_string(),
                params: json!({
                    "meeting_no": "TEST",
                    "task_desc": "local socket",
                    "dept": "QA",
                    "owner": "tester",
                    "required_date": "2026/09/01",
                    "actual_date": "",
                    "remark": "rpc"
                }),
            },
            Vec::new(),
        )
        .await;
        let task_id = created.header["result"]["id"].as_i64().unwrap();
        assert_eq!(created.header["result"]["actual_date"], "进行中");

        let payload = vec![0, 1, 2, 3, 254, 255];
        let uploaded = dispatch(
            &db,
            RequestHeader {
                id: 2,
                method: "attachment.upload".to_string(),
                params: json!({"task_id": task_id, "filename": "binary.dat"}),
            },
            payload.clone(),
        )
        .await;
        let attachment_id = uploaded.header["result"]["id"].as_i64().unwrap();

        let downloaded = dispatch(
            &db,
            RequestHeader {
                id: 3,
                method: "attachment.download".to_string(),
                params: json!({"id": attachment_id}),
            },
            Vec::new(),
        )
        .await;
        assert_eq!(downloaded.header["result"]["filename"], "binary.dat");
        assert_eq!(downloaded.binary, payload);

        let updated_payload = vec![9, 8, 7, 6];
        let updated = dispatch(
            &db,
            RequestHeader {
                id: 4,
                method: "attachment.update".to_string(),
                params: json!({"id": attachment_id, "filename": "updated.dat"}),
            },
            updated_payload.clone(),
        )
        .await;
        assert_eq!(updated.header["result"]["filename"], "updated.dat");

        let downloaded = dispatch(
            &db,
            RequestHeader {
                id: 5,
                method: "attachment.download".to_string(),
                params: json!({"id": attachment_id}),
            },
            Vec::new(),
        )
        .await;
        assert_eq!(downloaded.header["result"]["filename"], "updated.dat");
        assert_eq!(downloaded.binary, updated_payload);

        let _ = service::delete_attachment(&db, attachment_id).await;
        drop(db);
        std::fs::remove_file(db_path).ok();
    }

    #[tokio::test]
    async fn snapshot_rpc_stores_remark_usage_and_read_only_payload() {
        let unique = uuid::Uuid::new_v4();
        let db_path = std::env::temp_dir().join(format!("hyrwbz_rpc_snapshot_{unique}.db"));
        let db = crate::db::init(db_path.to_string_lossy().as_ref())
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO tasks
             (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark)
             VALUES ('纪要〔2026〕1号', 1, '历史任务', '', '', '', '进行中', '')",
        )
        .execute(&db)
        .await
        .unwrap();

        let created = dispatch(
            &db,
            RequestHeader {
                id: 10,
                method: "snapshot.create".to_string(),
                params: json!({"remark": "保存前检查"}),
            },
            Vec::new(),
        )
        .await;
        let snapshot_id = created.header["result"]["snapshot_id"]
            .as_i64()
            .unwrap();
        assert_eq!(created.header["result"]["used_count"], 1);

        let detail = dispatch(
            &db,
            RequestHeader {
                id: 11,
                method: "snapshot.get".to_string(),
                params: json!({"id": snapshot_id}),
            },
            Vec::new(),
        )
        .await;
        assert_eq!(detail.header["result"]["remark"], "保存前检查");
        assert_eq!(detail.header["result"]["tasks"][0]["task_desc"], "历史任务");

        db.close().await;
        std::fs::remove_file(db_path).ok();
    }

    #[tokio::test]
    async fn task_search_rpc_uses_separate_index_database() {
        let unique = uuid::Uuid::new_v4();
        let db_path = std::env::temp_dir().join(format!("hyrwbz_rpc_search_core_{unique}.db"));
        let index_path =
            std::env::temp_dir().join(format!("hyrwbz_rpc_search_index_{unique}.db"));
        let db = crate::db::init(db_path.to_string_lossy().as_ref())
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO tasks
             (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark)
             VALUES ('纪要〔2026〕1号', 1, '搜索目标', '工程部', '张三', '', '进行中', '')",
        )
        .execute(&db)
        .await
        .unwrap();
        let index = search_index::SearchIndex::open_at(
            &db,
            index_path.to_string_lossy().as_ref(),
        )
        .await
        .unwrap();
        let response = dispatch_inner(
            &db,
            None,
            Some(&index),
            RequestHeader {
                id: 9,
                method: "search.tasks".to_string(),
                params: json!({"query": "搜索目标 张三"}),
            },
            Vec::new(),
        )
        .await;
        assert_eq!(response.header["result"], json!([1]));

        drop(index);
        db.close().await;
        std::fs::remove_file(db_path).ok();
        std::fs::remove_file(index_path).ok();
    }

    #[cfg(windows)]
    #[tokio::test]
    async fn windows_local_socket_health_smoke() {
        use interprocess::local_socket::traits::tokio::Stream as _;

        let unique = uuid::Uuid::new_v4();
        let socket_path = format!(r"\\.\pipe\hyrwbz_test_{unique}");
        let db_path = std::env::temp_dir().join(format!("hyrwbz_test_{unique}.db"));
        let db = crate::db::init(db_path.to_string_lossy().as_ref())
            .await
            .unwrap();
        let server_path = socket_path.clone();
        let notification_store = notifications::NotificationStore::open().await.unwrap();
        let search_path = std::env::temp_dir().join(format!("hyrwbz_search_{unique}.db"));
        let search_index = search_index::SearchIndex::open_at(
            &db,
            search_path.to_string_lossy().as_ref(),
        )
        .await
        .unwrap();
        let server = tokio::spawn(async move {
            serve(&server_path, db, notification_store, search_index).await
        });

        let mut client = None;
        for _ in 0..50 {
            let name = socket_path.as_str().to_fs_name::<GenericFilePath>().unwrap();
            match Stream::connect(name).await {
                Ok(stream) => {
                    client = Some(stream);
                    break;
                }
                Err(_) => tokio::time::sleep(std::time::Duration::from_millis(20)).await,
            }
        }
        let mut client = client.expect("named pipe server did not become ready");
        let request = Frame {
            flags: 0,
            header: json!({"id": 1, "method": "system.health", "params": {}}),
            binary: Vec::new(),
        };
        write_frame(&mut client, &request).await.unwrap();
        let response = read_frame(&mut client).await.unwrap();
        assert_eq!(response.header["id"], 1);
        assert_eq!(response.header["result"]["ok"], true);
        server.abort();
        drop(client);
        std::fs::remove_file(db_path).ok();
        std::fs::remove_file(search_path).ok();
    }
}
