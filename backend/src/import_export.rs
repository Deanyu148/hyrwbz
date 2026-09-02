use crate::db::{self, Db};
use anyhow::Result;
use calamine::{open_workbook_auto, Data, Reader};
use chrono::Local;
use sqlx::{Acquire, Row};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

pub async fn export_db_file() -> Result<String> {
    let src = db::default_db_path();
    let dir = default_export_dir();
    fs::create_dir_all(&dir)?;
    let now = Local::now().format("%Y%m%d_%H%M%S").to_string();
    let dst = dir.join(format!("data_{}.db", now));
    fs::copy(&src, &dst)?;
    Ok(dst.to_string_lossy().to_string())
}

pub async fn export_all_files(db: &Db, out_dir: Option<String>) -> Result<String> {
    let now = Local::now().format("%Y%m%d_%H%M%S").to_string();
    let dir = out_dir
        .map(PathBuf::from)
        .unwrap_or_else(default_export_dir);
    let attachments = application_base().join("attachments");
    anyhow::ensure!(
        !dir.starts_with(&attachments),
        "导出目录不能位于附件目录内"
    );
    fs::create_dir_all(&dir)?;
    let output = dir.join(format!("hyrwbz_all_files_{}.zip", now));
    let snapshot = std::env::temp_dir().join(format!(
        "hyrwbz_bundle_{}.db",
        uuid::Uuid::new_v4()
    ));
    let escaped_snapshot = snapshot.to_string_lossy().replace('\'', "''");
    sqlx::query(&format!("VACUUM INTO '{}'", escaped_snapshot))
        .execute(db)
        .await?;

    let result = (|| -> Result<()> {
        let file = fs::File::create(&output)?;
        let mut writer = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated);
        writer.start_file("data.db", options)?;
        let mut database = fs::File::open(&snapshot)?;
        std::io::copy(&mut database, &mut writer)?;

        writer.add_directory("attachments/", options)?;
        if attachments.exists() {
            add_directory_to_zip(&mut writer, &attachments, "attachments", options)?;
        }
        writer.finish()?;
        Ok(())
    })();
    fs::remove_file(&snapshot).ok();
    if let Err(error) = result {
        fs::remove_file(&output).ok();
        return Err(error);
    }
    Ok(output.to_string_lossy().to_string())
}

pub async fn import_all_files(db: &Db, zip_path: &str) -> Result<()> {
    let staging = std::env::temp_dir().join(format!(
        "hyrwbz_bundle_import_{}",
        uuid::Uuid::new_v4()
    ));
    fs::create_dir_all(&staging)?;
    let result = async {
        let file = fs::File::open(zip_path)?;
        let mut archive = zip::ZipArchive::new(file)?;
        for index in 0..archive.len() {
            let mut entry = archive.by_index(index)?;
            let enclosed = entry
                .enclosed_name()
                .ok_or_else(|| anyhow::anyhow!("ZIP 包含不安全路径: {}", entry.name()))?
                .to_path_buf();
            let allowed = enclosed == Path::new("data.db")
                || enclosed.starts_with(Path::new("attachments"));
            if !allowed {
                continue;
            }
            let target = staging.join(&enclosed);
            if entry.is_dir() {
                fs::create_dir_all(&target)?;
            } else {
                if let Some(parent) = target.parent() {
                    fs::create_dir_all(parent)?;
                }
                let mut output = fs::File::create(&target)?;
                std::io::copy(&mut entry, &mut output)?;
            }
        }

        drop(archive);
        let database = staging.join("data.db");
        anyhow::ensure!(database.is_file(), "ZIP 中缺少 data.db");
        let staged_attachments = staging.join("attachments");
        fs::create_dir_all(&staged_attachments)?;
        import_db_file(db, database.to_string_lossy().as_ref()).await?;
        replace_attachments_directory(&staged_attachments)?;
        Ok::<(), anyhow::Error>(())
    }
    .await;
    fs::remove_dir_all(&staging).ok();
    result
}

fn application_base() -> PathBuf {
    let exe = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    exe.parent()
        .unwrap_or_else(|| Path::new("."))
        .to_path_buf()
}

fn add_directory_to_zip(
    writer: &mut zip::ZipWriter<fs::File>,
    directory: &Path,
    zip_prefix: &str,
    options: zip::write::SimpleFileOptions,
) -> Result<()> {
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let path = entry.path();
        let name = format!(
            "{}/{}",
            zip_prefix.trim_end_matches('/'),
            entry.file_name().to_string_lossy()
        )
        .replace('\\', "/");
        if path.is_dir() {
            writer.add_directory(format!("{}/", name), options)?;
            add_directory_to_zip(writer, &path, &name, options)?;
        } else if path.is_file() {
            writer.start_file(name, options)?;
            let mut input = fs::File::open(&path)?;
            std::io::copy(&mut input, writer)?;
        }
    }
    Ok(())
}

fn copy_directory(source: &Path, target: &Path) -> Result<()> {
    fs::create_dir_all(target)?;
    for entry in fs::read_dir(source)? {
        let entry = entry?;
        let source_path = entry.path();
        let target_path = target.join(entry.file_name());
        if source_path.is_dir() {
            copy_directory(&source_path, &target_path)?;
        } else if source_path.is_file() {
            fs::copy(&source_path, &target_path)?;
        }
    }
    Ok(())
}

fn replace_attachments_directory(source: &Path) -> Result<()> {
    let base = application_base();
    let target = base.join("attachments");
    let incoming = base.join(format!(
        "attachments_import_{}",
        uuid::Uuid::new_v4()
    ));
    let backup = base.join(format!(
        "attachments_backup_{}",
        uuid::Uuid::new_v4()
    ));
    copy_directory(source, &incoming)?;
    if target.exists() {
        fs::rename(&target, &backup)?;
    }
    if let Err(error) = fs::rename(&incoming, &target) {
        if backup.exists() {
            fs::rename(&backup, &target).ok();
        }
        fs::remove_dir_all(&incoming).ok();
        return Err(error.into());
    }
    fs::remove_dir_all(&backup).ok();
    Ok(())
}

pub async fn import_db_file(db: &Db, src_path: &str) -> Result<()> {
    // ATTACH DATABASE is connection-local in SQLite. Keep the attach, reads,
    // writes, and detach on one acquired connection; using the pool directly
    // can send each statement to a different connection and silently import
    // nothing when the attached schema is not visible there.
    let mut conn = db.acquire().await?;
    let escaped_path = src_path.replace('\'', "''");
    sqlx::query(&format!("ATTACH DATABASE '{}' AS import_src", escaped_path))
        .execute(&mut *conn)
        .await?;

    let import_result = async {
        let mut tx = conn.begin().await?;
        for table in &["tasks", "delays", "meta", "snapshots", "attachments"] {
            let count: i64 = sqlx::query_scalar(&format!(
                "SELECT count(*) FROM import_src.sqlite_master WHERE type='table' AND name='{}'",
                table
            ))
            .fetch_one(&mut *tx)
            .await?;
            if count == 0 {
                continue;
            }

            let del = format!("DELETE FROM {}", table);
            sqlx::query(&del).execute(&mut *tx).await?;
            if *table == "snapshots" {
                let source_columns = sqlx::query("PRAGMA import_src.table_info(snapshots)")
                    .fetch_all(&mut *tx)
                    .await?;
                let has_remark = source_columns.iter().any(|row| {
                    row.try_get::<String, _>("name")
                        .is_ok_and(|name| name == "remark")
                });
                let insert = if has_remark {
                    "INSERT INTO snapshots (snapshot_id, saved_at, remark, payload)
                     SELECT snapshot_id, saved_at, remark, payload FROM import_src.snapshots"
                } else {
                    "INSERT INTO snapshots (snapshot_id, saved_at, remark, payload)
                     SELECT snapshot_id, saved_at, '', payload FROM import_src.snapshots"
                };
                sqlx::query(insert).execute(&mut *tx).await?;
            } else {
                let ins = format!("INSERT INTO {} SELECT * FROM import_src.{}", table, table);
                sqlx::query(&ins).execute(&mut *tx).await?;
            }
        }
        tx.commit().await?;
        Ok::<(), anyhow::Error>(())
    }
    .await;

    // The transaction is committed or dropped before DETACH is attempted.
    let detach_result = sqlx::query("DETACH DATABASE import_src")
        .execute(&mut *conn)
        .await;
    import_result?;
    detach_result?;
    Ok(())
}

pub async fn create_snapshot(
    db: &Db,
    remark: Option<String>,
) -> Result<crate::models::SnapshotCreateResult> {
    let tasks = crate::service::list_tasks(db, &crate::models::FilterReq::default())
        .await
        .map_err(|error| anyhow::anyhow!("{}", error.message))?;
    let payload = serde_json::to_string(&tasks)?;
    let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    let remark = remark.unwrap_or_default().trim().to_string();
    let mut tx = db.begin().await?;
    let result = sqlx::query(
        "INSERT INTO snapshots (saved_at, remark, payload) VALUES (?1, ?2, ?3)",
    )
    .bind(&now)
    .bind(&remark)
    .bind(&payload)
    .execute(&mut *tx)
    .await?;
    let snapshot_id = result.last_insert_rowid();
    sqlx::query(
        "DELETE FROM snapshots WHERE snapshot_id NOT IN (
            SELECT snapshot_id FROM snapshots ORDER BY snapshot_id DESC LIMIT 5
        )",
    )
    .execute(&mut *tx)
    .await?;
    let used_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM snapshots")
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(crate::models::SnapshotCreateResult {
        snapshot_id,
        used_count,
    })
}

pub async fn list_snapshots(db: &Db) -> Result<Vec<crate::models::SnapshotInfo>> {
    let rows = sqlx::query(
        "SELECT snapshot_id, saved_at, remark
         FROM snapshots ORDER BY snapshot_id DESC LIMIT 5",
    )
    .fetch_all(db)
    .await?;
    Ok(rows
        .iter()
        .map(|row| crate::models::SnapshotInfo {
            snapshot_id: row.try_get("snapshot_id").unwrap_or_default(),
            saved_at: row.try_get("saved_at").unwrap_or_default(),
            remark: row.try_get("remark").unwrap_or_default(),
        })
        .collect())
}

pub async fn get_snapshot(db: &Db, snapshot_id: i64) -> Result<crate::models::SnapshotDetail> {
    let row = sqlx::query(
        "SELECT snapshot_id, saved_at, remark, payload
         FROM snapshots WHERE snapshot_id = ?1",
    )
    .bind(snapshot_id)
    .fetch_optional(db)
    .await?
    .ok_or_else(|| anyhow::anyhow!("历史快照不存在"))?;
    let payload: String = row.try_get("payload")?;
    let tasks = serde_json::from_str(&payload)?;
    Ok(crate::models::SnapshotDetail {
        snapshot_id: row.try_get("snapshot_id")?,
        saved_at: row.try_get("saved_at")?,
        remark: row.try_get("remark").unwrap_or_default(),
        tasks,
    })
}

fn default_export_dir() -> PathBuf {
    // 数据库导出目录放在 exe 同目录下的 exports/（安装目录）
    let exe = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    let dir = exe.parent().unwrap_or_else(|| std::path::Path::new("."));
    dir.join("exports")
}

#[derive(serde::Serialize)]
pub struct ImportResult {
    pub imported: usize,
    pub errors: Vec<String>,
}

pub async fn import_excel(
    db: &Db,
    file_path: &str,
    move_remark_to_delay_reason: bool,
) -> Result<ImportResult> {
    // 自动识别 xlsx/xls/xlsm 等格式；仅支持 Xlsx 时打开老版二进制 .xls
    // 会报 "Zip error: ... Could not find EOCD"
    let mut workbook = match open_workbook_auto(file_path) {
        Ok(wb) => wb,
        // 部分"精简生成器"导出的文件缺 xl/_rels/workbook.xml.rels，
        // 自动补上该文件后重试
        Err(e) if e.to_string().contains("workbook.xml.rels") => {
            let repaired = repair_xlsx_missing_rels(file_path)
                .map_err(|re| anyhow::anyhow!("打开 Excel 失败: {}（自动修复失败: {}）", e, re))?;
            let res = open_workbook_auto(&repaired);
            fs::remove_file(&repaired).ok();
            res.map_err(|e2| anyhow::anyhow!("打开 Excel 失败（已尝试自动修复）: {}", e2))?
        }
        Err(e) => {
            return Err(anyhow::anyhow!(
                "打开 Excel 失败（请确认文件为有效的 xlsx/xls 格式）: {}",
                e
            ))
        }
    };
    let sheet_names = workbook.sheet_names().to_vec();
    let sheet_name = sheet_names
        .first()
        .ok_or_else(|| anyhow::anyhow!("no sheets"))?;
    let range = workbook
        .worksheet_range(sheet_name)
        .map_err(|e| anyhow::anyhow!("read sheet: {}", e))?;

    let rows: Vec<Vec<String>> = range
        .rows()
        .map(|r| r.iter().map(cell_to_string).collect())
        .collect();
    import_rows(db, rows, move_remark_to_delay_reason).await
}

/// 修复缺少 xl/_rels/workbook.xml.rels 的 xlsx：按 xl/workbook.xml 中的
/// sheet 声明生成最小关系文件，重写 zip 后返回新文件路径。
fn repair_xlsx_missing_rels(src: &str) -> Result<PathBuf> {
    let file = fs::File::open(src)?;
    let mut archive = zip::ZipArchive::new(file)?;

    // 读取 xl/workbook.xml
    let mut workbook_xml = String::new();
    for i in 0..archive.len() {
        let mut f = archive.by_index(i)?;
        if f.name() == "xl/workbook.xml" {
            f.read_to_string(&mut workbook_xml)?;
            break;
        }
    }
    anyhow::ensure!(!workbook_xml.is_empty(), "压缩包中未找到 xl/workbook.xml");

    // 逐个提取 <sheet .../> 标签的属性，生成对应 Relationship
    let mut rels = String::from(
        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n\
         <Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">",
    );
    let mut idx = 0usize;
    let mut rest = workbook_xml.as_str();
    while let Some(p) = rest.find("<sheet ") {
        let tag_end = p + rest[p..]
            .find('>')
            .ok_or_else(|| anyhow::anyhow!("workbook.xml 中 <sheet> 标签未闭合"))?;
        let tag = &rest[p..tag_end];
        idx += 1;
        let rid = extract_xml_attr(tag, "r:id").unwrap_or_else(|| format!("rId{}", idx));
        let sheet_id = extract_xml_attr(tag, "sheetId").unwrap_or_else(|| idx.to_string());
        rels.push_str(&format!(
            "<Relationship Id=\"{}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet{}.xml\"/>",
            rid, sheet_id
        ));
        rest = &rest[tag_end..];
    }
    anyhow::ensure!(idx > 0, "workbook.xml 中未找到工作表");
    rels.push_str("</Relationships>");

    // 重写 zip：复制全部条目并插入缺失的 rels
    let dst = std::env::temp_dir().join(format!("hyrwbz_repair_{}.xlsx", uuid::Uuid::new_v4()));
    let mut zw = zip::ZipWriter::new(fs::File::create(&dst)?);
    for i in 0..archive.len() {
        let mut f = archive.by_index(i)?;
        if f.is_dir() {
            continue;
        }
        let name = f.name().to_string();
        let mut buf = Vec::new();
        f.read_to_end(&mut buf)?;
        zw.start_file(name, zip::write::SimpleFileOptions::default())?;
        zw.write_all(&buf)?;
    }
    zw.start_file(
        "xl/_rels/workbook.xml.rels",
        zip::write::SimpleFileOptions::default(),
    )?;
    zw.write_all(rels.as_bytes())?;
    zw.finish()?;
    Ok(dst)
}

/// 从 XML 标签字符串中提取 `attr="value"` 属性值。
fn extract_xml_attr(tag: &str, attr: &str) -> Option<String> {
    let pat = format!("{}=\"", attr);
    let start = tag.find(&pat)? + pat.len();
    let end = start + tag[start..].find('"')?;
    Some(tag[start..end].to_string())
}

/// 导入 CSV（第一行为表头）。
/// 自动处理 UTF-8/GBK 编码（国内 Excel 另存的 CSV 常为 GBK），兼容 UTF-8 BOM。
pub async fn import_csv(
    db: &Db,
    file_path: &str,
    move_remark_to_delay_reason: bool,
) -> Result<ImportResult> {
    let bytes = fs::read(file_path)?;
    let (text, _, had_errors) = encoding_rs::UTF_8.decode(&bytes);
    let text = if had_errors {
        encoding_rs::GBK.decode(&bytes).0
    } else {
        text
    };

    let mut reader = csv::ReaderBuilder::new()
        .has_headers(false)
        .flexible(true)
        .from_reader(text.as_bytes());
    let rows: Vec<Vec<String>> = reader
        .records()
        .filter_map(|r| r.ok())
        .map(|r| r.iter().map(|s| s.to_string()).collect())
        .collect();
    import_rows(db, rows, move_remark_to_delay_reason).await
}

/// 按模板列（序号/会议纪要号/任务序号/任务内容/...）导入数据行，Excel 与 CSV 共用。
async fn import_rows(
    db: &Db,
    rows: Vec<Vec<String>>,
    move_remark_to_delay_reason: bool,
) -> Result<ImportResult> {
    if rows.is_empty() {
        return Ok(ImportResult {
            imported: 0,
            errors: vec![],
        });
    }

    let headers: Vec<String> = rows[0].iter().map(|c| c.trim().to_string()).collect();
    let find_col = |name: &str| headers.iter().position(|h| h == name);

    let col_meeting = find_col("会议纪要号");
    let col_task_no = find_col("任务序号");
    let col_desc = find_col("任务内容");
    let col_dept = find_col("责任部门");
    let col_owner = find_col("责任人");
    let col_required = find_col("计划完成时间");
    let col_delay = find_col("延期时间").or_else(|| find_col("延期1"));
    let col_actual = find_col("实际完成时间");
    let col_remark = find_col("备注");

    let mut imported = 0;
    let errors: Vec<String> = Vec::new();

    for row in rows.iter().skip(1) {
        let get_str = |col: Option<usize>| -> String {
            match col {
                Some(i) if i < row.len() => row[i].trim().to_string(),
                _ => String::new(),
            }
        };

        let meeting_no = get_str(col_meeting);
        if meeting_no.is_empty() {
            continue;
        }
        let task_no: i64 = get_str(col_task_no).parse().unwrap_or(0);
        if task_no == 0 {
            continue;
        }

        let task_desc = get_str(col_desc);
        let dept = normalize_english_commas(&get_str(col_dept));
        let owner = normalize_english_commas(&get_str(col_owner));
        let required_date = get_str(col_required);
        let actual_date = get_str(col_actual);
        let actual_date = if actual_date.is_empty() {
            "进行中".to_string()
        } else {
            actual_date
        };
        let remark = get_str(col_remark);
        let delay_date = get_str(col_delay);
        // 延期理由依赖延期记录。没有延期时间时保留任务备注，避免内容丢失。
        let move_remark = move_remark_to_delay_reason && !delay_date.is_empty();
        let task_remark = if move_remark { "" } else { remark.as_str() };
        let delay_reason = if move_remark { remark.as_str() } else { "" };

        let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();

        let existing: Option<i64> =
            sqlx::query_scalar("SELECT id FROM tasks WHERE meeting_no = ?1 AND task_no = ?2")
                .bind(&meeting_no)
                .bind(task_no)
                .fetch_optional(db)
                .await?;

        let task_id = if let Some(id) = existing {
            sqlx::query(
                "UPDATE tasks SET meeting_no=?1, task_no=?2, task_desc=?3, dept=?4, owner=?5,
                 required_date=?6, actual_date=?7, remark=?8, updated_at=?9 WHERE id=?10",
            )
            .bind(&meeting_no)
            .bind(task_no)
            .bind(&task_desc)
            .bind(&dept)
            .bind(&owner)
            .bind(&required_date)
            .bind(&actual_date)
            .bind(task_remark)
            .bind(&now)
            .bind(id)
            .execute(db)
            .await?;
            id
        } else {
            let res = sqlx::query(
                "INSERT INTO tasks (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)",
            ).bind(&meeting_no).bind(task_no).bind(&task_desc).bind(&dept)
            .bind(&owner).bind(&required_date).bind(&actual_date).bind(task_remark)
            .bind(&now).execute(db).await?;
            res.last_insert_rowid()
        };

        if !delay_date.is_empty() {
            let existing_delay: Option<i64> =
                sqlx::query_scalar("SELECT id FROM delays WHERE task_id = ?1 AND delay_date = ?2")
                    .bind(task_id)
                    .bind(&delay_date)
                    .fetch_optional(db)
                    .await?;
            if let Some(delay_id) = existing_delay {
                if move_remark && !delay_reason.is_empty() {
                    sqlx::query("UPDATE delays SET delay_reason = ?1 WHERE id = ?2")
                        .bind(delay_reason)
                        .bind(delay_id)
                        .execute(db)
                        .await?;
                }
            } else {
                sqlx::query(
                    "INSERT INTO delays (task_id, meeting_no, task_no, delay_date, delay_reason, created_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                )
                .bind(task_id)
                .bind(&meeting_no)
                .bind(task_no)
                .bind(&delay_date)
                .bind(delay_reason)
                .bind(&now)
                .execute(db)
                .await?;
            }
        }

        imported += 1;
    }

    Ok(ImportResult { imported, errors })
}

/// 导出 CSV（UTF-8 带 BOM，Excel 可直接打开不乱码）。
/// 列结构同 template.csv；一条任务有多条延期记录时取第一条延期日期。
pub async fn export_csv(
    db: &Db,
    filter: crate::models::FilterReq,
    out_dir: Option<String>,
) -> Result<String> {
    let tasks = crate::service::list_tasks(db, &filter)
        .await
        .map_err(|e| anyhow::anyhow!("list tasks: {}", e.message))?;

    let now = Local::now().format("%Y%m%d_%H%M%S").to_string();
    let dir = out_dir
        .map(PathBuf::from)
        .unwrap_or_else(default_export_dir);
    fs::create_dir_all(&dir)?;
    let path = dir.join(format!("hyrwbz_export_{}.csv", now));

    let mut file = fs::File::create(&path)?;
    // UTF-8 BOM，保证 Excel 打开中文不乱码
    file.write_all(&[0xEF, 0xBB, 0xBF])?;

    let mut w = csv::Writer::from_writer(file);
    w.write_record(&[
        "序号",
        "会议纪要号",
        "任务序号",
        "任务内容",
        "责任部门",
        "责任人",
        "计划完成时间",
        "延期时间",
        "实际完成时间",
        "备注",
    ])?;
    for (i, t) in tasks.iter().enumerate() {
        let delay_date = t
            .delays
            .first()
            .map(|d| d.delay_date.as_str())
            .unwrap_or("");
        w.write_record(&[
            (i + 1).to_string(),
            t.meeting_no.clone(),
            t.task_no.to_string(),
            t.task_desc.clone(),
            t.dept.clone(),
            t.owner.clone(),
            t.required_date.clone(),
            delay_date.to_string(),
            t.actual_date.clone(),
            t.remark.clone(),
        ])?;
    }
    w.flush()?;
    Ok(path.to_string_lossy().to_string())
}

fn normalize_english_commas(value: &str) -> String {
    value
        .chars()
        .map(|character| match character {
            '，' | '、' | '﹐' | '﹑' | '､' | '،' => ',',
            _ => character,
        })
        .collect()
}

fn cell_to_string(cell: &Data) -> String {
    match cell {
        Data::Empty => String::new(),
        Data::String(s) => s.clone(),
        Data::Int(i) => i.to_string(),
        Data::Float(f) => f.to_string(),
        Data::DateTime(d) => d.to_string(),
        _ => String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn import_headers() -> Vec<String> {
        [
            "序号",
            "会议纪要号",
            "任务序号",
            "任务内容",
            "责任部门",
            "责任人",
            "计划完成时间",
            "延期时间",
            "实际完成时间",
            "备注",
        ]
        .into_iter()
        .map(str::to_string)
        .collect()
    }

    async fn test_db(name: &str) -> (Db, PathBuf) {
        let path = std::env::temp_dir().join(format!(
            "hyrwbz_import_{name}_{}.db",
            uuid::Uuid::new_v4()
        ));
        let db = crate::db::init(path.to_string_lossy().as_ref())
            .await
            .unwrap();
        (db, path)
    }

    fn write_excel(path: &std::path::Path, rows: &[Vec<String>]) {
        let mut workbook = rust_xlsxwriter::Workbook::new();
        let sheet = workbook.add_worksheet();
        for (row_index, row) in rows.iter().enumerate() {
            for (column_index, value) in row.iter().enumerate() {
                sheet
                    .write(row_index as u32, column_index as u16, value)
                    .unwrap();
            }
        }
        workbook.save(path).unwrap();
    }

    fn write_csv(path: &std::path::Path, rows: &[Vec<String>]) {
        let mut writer = csv::Writer::from_path(path).unwrap();
        for row in rows {
            writer.write_record(row).unwrap();
        }
        writer.flush().unwrap();
    }

    #[tokio::test]
    async fn snapshots_store_optional_remark_and_keep_five_entries() {
        let (db, db_path) = test_db("snapshot_remark").await;
        sqlx::query(
            "INSERT INTO tasks
             (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark)
             VALUES ('纪要〔2026〕1号', 1, '快照任务', '', '', '', '进行中', '')",
        )
        .execute(&db)
        .await
        .unwrap();

        for index in 1i64..=6 {
            let result = create_snapshot(&db, Some(format!("备注{index}")))
                .await
                .unwrap();
            assert_eq!(result.used_count, index.min(5));
        }
        let snapshots = list_snapshots(&db).await.unwrap();
        assert_eq!(snapshots.len(), 5);
        assert_eq!(snapshots.first().unwrap().remark, "备注6");
        assert_eq!(snapshots.last().unwrap().remark, "备注2");

        let detail = get_snapshot(&db, snapshots.first().unwrap().snapshot_id)
            .await
            .unwrap();
        assert_eq!(detail.remark, "备注6");
        assert_eq!(detail.tasks.len(), 1);
        assert_eq!(detail.tasks[0].task_desc, "快照任务");

        db.close().await;
        fs::remove_file(db_path).ok();
    }

    #[tokio::test]
    async fn database_import_reads_attached_database_on_one_connection() {
        let (target, target_path) = test_db("target_pool").await;
        let (source, source_path) = test_db("source_pool").await;

        sqlx::query(
            "INSERT INTO tasks (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark)
             VALUES ('旧数据', 1, '旧任务', '', '', '', '进行中', '')",
        )
        .execute(&target)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO tasks (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark)
             VALUES ('导入数据', 2, '导入任务', '部门', '责任人', '', '进行中', '')",
        )
        .execute(&source)
        .await
        .unwrap();
        drop(source);

        import_db_file(&target, source_path.to_string_lossy().as_ref())
            .await
            .unwrap();

        let rows: Vec<(String, String)> = sqlx::query_as(
            "SELECT meeting_no, task_desc FROM tasks ORDER BY id",
        )
        .fetch_all(&target)
        .await
        .unwrap();
        assert_eq!(rows, vec![("导入数据".to_string(), "导入任务".to_string())]);

        drop(target);
        fs::remove_file(target_path).ok();
        fs::remove_file(source_path).ok();
    }

    #[test]
    fn bundle_zip_contains_nested_attachments() {
        let root = std::env::temp_dir().join(format!(
            "hyrwbz_bundle_test_{}",
            uuid::Uuid::new_v4()
        ));
        let attachments = root.join("attachments").join("MEETING").join("1");
        fs::create_dir_all(&attachments).unwrap();
        fs::write(attachments.join("file.txt"), b"content").unwrap();
        let zip_path = root.join("bundle.zip");
        let file = fs::File::create(&zip_path).unwrap();
        let mut writer = zip::ZipWriter::new(file);
        let options = zip::write::SimpleFileOptions::default();
        writer.add_directory("attachments/", options).unwrap();
        add_directory_to_zip(&mut writer, &root.join("attachments"), "attachments", options)
            .unwrap();
        writer.finish().unwrap();

        let file = fs::File::open(&zip_path).unwrap();
        let mut archive = zip::ZipArchive::new(file).unwrap();
        let mut entry = archive
            .by_name("attachments/MEETING/1/file.txt")
            .unwrap();
        let mut content = String::new();
        entry.read_to_string(&mut content).unwrap();
        assert_eq!(content, "content");
        drop(entry);
        drop(archive);
        fs::remove_dir_all(root).ok();
    }

    #[tokio::test]
    async fn excel_import_can_move_remark_to_delay_reason() {
        let (db, db_path) = test_db("move_remark").await;
        let input_path = std::env::temp_dir().join(format!(
            "hyrwbz_import_{}.xlsx",
            uuid::Uuid::new_v4()
        ));
        let rows = vec![
            import_headers(),
            vec![
                "1", "MEETING-1", "1", "任务", "部门", "责任人", "2026/09/01",
                "2026/09/02", "", "需要延期",
            ]
            .into_iter()
            .map(str::to_string)
            .collect(),
            vec![
                "2", "MEETING-1", "2", "无延期任务", "部门", "责任人", "2026/09/01",
                "", "", "无延期时保留备注",
            ]
            .into_iter()
            .map(str::to_string)
            .collect(),
        ];
        write_excel(&input_path, &rows);

        let result = import_excel(&db, input_path.to_string_lossy().as_ref(), true)
            .await
            .unwrap();
        assert_eq!(result.imported, 2);

        let moved_task = sqlx::query(
            "SELECT id, remark FROM tasks WHERE meeting_no = 'MEETING-1' AND task_no = 1",
        )
        .fetch_one(&db)
        .await
        .unwrap();
        let task_id: i64 = moved_task.try_get("id").unwrap();
        let task_remark: String = moved_task.try_get("remark").unwrap();
        assert_eq!(task_remark, "");

        let delay =
            sqlx::query("SELECT delay_date, delay_reason FROM delays WHERE task_id = ?1")
                .bind(task_id)
                .fetch_one(&db)
                .await
                .unwrap();
        assert_eq!(
            delay.try_get::<String, _>("delay_date").unwrap(),
            "2026/09/02"
        );
        assert_eq!(
            delay.try_get::<String, _>("delay_reason").unwrap(),
            "需要延期"
        );

        let kept_remark: String = sqlx::query_scalar(
            "SELECT remark FROM tasks WHERE meeting_no = 'MEETING-1' AND task_no = 2",
        )
        .fetch_one(&db)
        .await
        .unwrap();
        assert_eq!(kept_remark, "无延期时保留备注");

        db.close().await;
        std::fs::remove_file(db_path).ok();
        std::fs::remove_file(input_path).ok();
    }

    #[tokio::test]
    async fn csv_import_respects_remark_move_option() {
        let (db, db_path) = test_db("keep_remark").await;
        let input_path = std::env::temp_dir().join(format!(
            "hyrwbz_import_{}.csv",
            uuid::Uuid::new_v4()
        ));
        let rows = vec![
            import_headers(),
            vec![
                "1", "MEETING-2", "1", "任务", "部门一，部门二、部门三", "张三，李四、王五", "2026/09/01",
                "2026/09/03", "", "继续保留",
            ]
            .into_iter()
            .map(str::to_string)
            .collect(),
        ];
        write_csv(&input_path, &rows);

        import_csv(&db, input_path.to_string_lossy().as_ref(), false)
            .await
            .unwrap();

        let task = sqlx::query(
            "SELECT id, remark, dept, owner FROM tasks WHERE meeting_no = 'MEETING-2' AND task_no = 1",
        )
        .fetch_one(&db)
        .await
        .unwrap();
        let task_id: i64 = task.try_get("id").unwrap();
        assert_eq!(task.try_get::<String, _>("remark").unwrap(), "继续保留");
        assert_eq!(
            task.try_get::<String, _>("dept").unwrap(),
            "部门一,部门二,部门三"
        );
        assert_eq!(
            task.try_get::<String, _>("owner").unwrap(),
            "张三,李四,王五"
        );

        let reason: String =
            sqlx::query_scalar("SELECT delay_reason FROM delays WHERE task_id = ?1")
                .bind(task_id)
                .fetch_one(&db)
                .await
                .unwrap();
        assert_eq!(reason, "");

        // 再次导入同一文件并启用移动选项，应清空任务备注并更新已有延期记录。
        import_csv(&db, input_path.to_string_lossy().as_ref(), true)
            .await
            .unwrap();
        let task_remark: String = sqlx::query_scalar(
            "SELECT remark FROM tasks WHERE meeting_no = 'MEETING-2' AND task_no = 1",
        )
        .fetch_one(&db)
        .await
        .unwrap();
        assert_eq!(task_remark, "");
        let moved_reason: String =
            sqlx::query_scalar("SELECT delay_reason FROM delays WHERE task_id = ?1")
                .bind(task_id)
                .fetch_one(&db)
                .await
                .unwrap();
        assert_eq!(moved_reason, "继续保留");

        db.close().await;
        std::fs::remove_file(db_path).ok();
        std::fs::remove_file(input_path).ok();
    }
}
