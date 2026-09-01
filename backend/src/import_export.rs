use crate::db::{self, Db};
use crate::models::FilterReq;
use anyhow::Result;
use chrono::Local;
use calamine::{Data, Reader, open_workbook_auto};
use sqlx::Row;
use std::fs;
use std::io::{Read, Write};
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

pub async fn import_db_file(db: &Db, src_path: &str) -> Result<()> {
    // Use ATTACH/INSERT to safely import while server is running
    let escaped_path = src_path.replace('\'', "''");
    sqlx::query(&format!("ATTACH DATABASE '{}' AS import_src", escaped_path))
        .execute(db).await?;

    for table in &["tasks", "delays", "meta", "snapshots", "attachments"] {
        // Check if source table exists
        let count: i64 = sqlx::query_scalar(
            &format!("SELECT count(*) FROM import_src.sqlite_master WHERE type='table' AND name='{}'", table)
        ).fetch_one(db).await.unwrap_or(0);
        if count == 0 { continue; }

        let mut tx = db.begin().await?;
        let del = format!("DELETE FROM {}", table);
        if let Err(e) = sqlx::query(&del).execute(&mut *tx).await {
            tx.rollback().await?;
            eprintln!("delete {}: {}", table, e);
            continue;
        }
        let ins = format!("INSERT INTO {} SELECT * FROM import_src.{}", table, table);
        if let Err(e) = sqlx::query(&ins).execute(&mut *tx).await {
            tx.rollback().await?;
            eprintln!("import {}: {}", table, e);
            continue;
        }
        tx.commit().await?;
    }

    let _ = sqlx::query("DETACH DATABASE import_src").execute(db).await;
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

pub async fn import_excel(db: &Db, file_path: &str) -> Result<ImportResult> {
    // 自动识别 xlsx/xls/xlsm 等格式；仅支持 Xlsx 时打开老版二进制 .xls
    // 会报 "Zip error: ... Could not find EOCD"
    let mut workbook = match open_workbook_auto(file_path) {
        Ok(wb) => wb,
        // 部分"精简生成器"导出的文件缺 xl/_rels/workbook.xml.rels，
        // 自动补上该文件后重试
        Err(e) if e.to_string().contains("workbook.xml.rels") => {
            let repaired = repair_xlsx_missing_rels(file_path).map_err(|re| {
                anyhow::anyhow!("打开 Excel 失败: {}（自动修复失败: {}）", e, re)
            })?;
            let res = open_workbook_auto(&repaired);
            fs::remove_file(&repaired).ok();
            res.map_err(|e2| {
                anyhow::anyhow!("打开 Excel 失败（已尝试自动修复）: {}", e2)
            })?
        }
        Err(e) => {
            return Err(anyhow::anyhow!(
                "打开 Excel 失败（请确认文件为有效的 xlsx/xls 格式）: {}", e
            ))
        }
    };
    let sheet_names = workbook.sheet_names().to_vec();
    let sheet_name = sheet_names.first().ok_or_else(|| anyhow::anyhow!("no sheets"))?;
    let range = workbook.worksheet_range(sheet_name)
        .map_err(|e| anyhow::anyhow!("read sheet: {}", e))?;

    let rows: Vec<Vec<String>> = range
        .rows()
        .map(|r| r.iter().map(cell_to_string).collect())
        .collect();
    import_rows(db, rows).await
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
        let tag_end = p + rest[p..].find('>')
            .ok_or_else(|| anyhow::anyhow!("workbook.xml 中 <sheet> 标签未闭合"))?;
        let tag = &rest[p..tag_end];
        idx += 1;
        let rid = extract_xml_attr(tag, "r:id").unwrap_or_else(|| format!("rId{}", idx));
        let sheet_id =
            extract_xml_attr(tag, "sheetId").unwrap_or_else(|| idx.to_string());
        rels.push_str(&format!(
            "<Relationship Id=\"{}\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet{}.xml\"/>",
            rid, sheet_id
        ));
        rest = &rest[tag_end..];
    }
    anyhow::ensure!(idx > 0, "workbook.xml 中未找到工作表");
    rels.push_str("</Relationships>");

    // 重写 zip：复制全部条目并插入缺失的 rels
    let dst = std::env::temp_dir()
        .join(format!("hyrwbz_repair_{}.xlsx", uuid::Uuid::new_v4()));
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
    zw.start_file("xl/_rels/workbook.xml.rels", zip::write::SimpleFileOptions::default())?;
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
pub async fn import_csv(db: &Db, file_path: &str) -> Result<ImportResult> {
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
    import_rows(db, rows).await
}

/// 按模板列（序号/会议纪要号/任务序号/任务内容/...）导入数据行，Excel 与 CSV 共用。
async fn import_rows(db: &Db, rows: Vec<Vec<String>>) -> Result<ImportResult> {
    if rows.is_empty() {
        return Ok(ImportResult { imported: 0, errors: vec![] });
    }

    let headers: Vec<String> = rows[0].iter().map(|c| c.trim().to_string()).collect();
    let find_col = |name: &str| headers.iter().position(|h| h == name);

    let col_meeting = find_col("会议纪要号");
    let col_task_no = find_col("任务序号");
    let col_desc = find_col("任务内容");
    let col_dept = find_col("责任部门");
    let col_owner = find_col("责任人");
    let col_required = find_col("计划完成时间");
    let col_delay = find_col("延期时间");
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
        if meeting_no.is_empty() { continue; }
        let task_no: i64 = get_str(col_task_no).parse().unwrap_or(0);
        if task_no == 0 { continue; }

        let task_desc = get_str(col_desc);
        let dept = get_str(col_dept);
        let owner = get_str(col_owner);
        let required_date = get_str(col_required);
        let actual_date = get_str(col_actual);
        let remark = get_str(col_remark);
        let delay_date = get_str(col_delay);

        let now = Local::now().format("%Y-%m-%d %H:%M:%S").to_string();

        let existing: Option<i64> = sqlx::query_scalar(
            "SELECT id FROM tasks WHERE meeting_no = ?1 AND task_no = ?2",
        ).bind(&meeting_no).bind(task_no).fetch_optional(db).await?;

        let task_id = if let Some(id) = existing {
            sqlx::query(
                "UPDATE tasks SET meeting_no=?1, task_no=?2, task_desc=?3, dept=?4, owner=?5,
                 required_date=?6, actual_date=?7, remark=?8, updated_at=?9 WHERE id=?10",
            ).bind(&meeting_no).bind(task_no).bind(&task_desc).bind(&dept)
            .bind(&owner).bind(&required_date).bind(&actual_date).bind(&remark)
            .bind(&now).bind(id).execute(db).await?;
            id
        } else {
            let res = sqlx::query(
                "INSERT INTO tasks (meeting_no, task_no, task_desc, dept, owner, required_date, actual_date, remark, created_at, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?9)",
            ).bind(&meeting_no).bind(task_no).bind(&task_desc).bind(&dept)
            .bind(&owner).bind(&required_date).bind(&actual_date).bind(&remark)
            .bind(&now).execute(db).await?;
            res.last_insert_rowid()
        };

        if !delay_date.is_empty() {
            let existing_delay: Option<i64> = sqlx::query_scalar(
                "SELECT id FROM delays WHERE task_id = ?1 AND delay_date = ?2",
            ).bind(task_id).bind(&delay_date).fetch_optional(db).await?;
            if existing_delay.is_none() {
                sqlx::query(
                    "INSERT INTO delays (task_id, meeting_no, task_no, delay_date, delay_reason, created_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                ).bind(task_id).bind(&meeting_no).bind(task_no).bind(&delay_date).bind("").bind(&now)
                .execute(db).await?;
            }
        }

        imported += 1;
    }

    Ok(ImportResult { imported, errors })
}

/// 导出 CSV（UTF-8 带 BOM，Excel 可直接打开不乱码）。
/// 列结构同 template.csv；一条任务有多条延期记录时取第一条延期日期。
pub async fn export_csv(db: &Db, filter: FilterReq, out_dir: Option<String>) -> Result<String> {
    let tasks = crate::handlers::list_tasks_inner(db, &filter)
        .await
        .map_err(|e| anyhow::anyhow!("list tasks: {}", e.1))?;

    let now = Local::now().format("%Y%m%d_%H%M%S").to_string();
    let dir = out_dir.map(PathBuf::from).unwrap_or_else(default_export_dir);
    fs::create_dir_all(&dir)?;
    let path = dir.join(format!("hyrwbz_export_{}.csv", now));

    let mut file = fs::File::create(&path)?;
    // UTF-8 BOM，保证 Excel 打开中文不乱码
    file.write_all(&[0xEF, 0xBB, 0xBF])?;

    let mut w = csv::Writer::from_writer(file);
    w.write_record(&[
        "序号", "会议纪要号", "任务序号", "任务内容", "责任部门", "责任人",
        "计划完成时间", "延期时间", "实际完成时间", "备注",
    ])?;
    for (i, t) in tasks.iter().enumerate() {
        let delay_date = t.delays.first().map(|d| d.delay_date.as_str()).unwrap_or("");
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
