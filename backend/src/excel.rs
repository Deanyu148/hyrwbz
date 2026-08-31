use crate::db::Db;
use crate::models::*;
use anyhow::Result;
use chrono::Local;
use rust_xlsxwriter::{Format, Workbook};
use sqlx::Row;
use std::fs;
use std::path::PathBuf;

pub async fn export(
    db: &Db,
    filter: FilterReq,
    out_dir: Option<String>,
) -> Result<ExportResult> {
    let tasks = crate::handlers::list_tasks_inner(db, &filter)
        .await
        .map_err(|e| anyhow::anyhow!("list tasks: {}", e.1))?;

    let mut wb = Workbook::new();
    let title_fmt = Format::new().set_bold().set_background_color("DDDDDD");
    let center = Format::new().set_align(rust_xlsxwriter::FormatAlign::Center);

    // Sheet1: 当前数据
    let sheet1 = wb.add_worksheet();
    sheet1.set_name("当前数据")?;
    write_sheet(sheet1, &tasks, &title_fmt, &center)?;

    // 历史 snapshots
    let snaps = sqlx::query("SELECT snapshot_id, saved_at, payload FROM snapshots ORDER BY snapshot_id DESC LIMIT 5")
        .fetch_all(db)
        .await?;
    let sorted: Vec<(String, String)> = snaps.iter().rev().map(|r| {
        let saved_at: String = r.try_get("saved_at").unwrap_or_default();
        let payload: String = r.try_get("payload").unwrap_or_default();
        (saved_at, payload)
    }).collect();

    // 仅保留 5 份，倒序：Sheet2 = 第一份历史（最早），即倒序后第一个
    let mut sheets_names: Vec<String> = vec!["当前数据".to_string()];
    for (saved_at, payload) in &sorted {
        let snap_tasks: Vec<Task> = serde_json::from_str(payload).unwrap_or_default();
        let sheet_name = format_sheet_name(saved_at);
        let sh = wb.add_worksheet();
        sh.set_name(&sheet_name)?;
        write_sheet(sh, &snap_tasks, &title_fmt, &center)?;
        sheets_names.push(sheet_name);
    }

    let now = Local::now().format("%Y%m%d_%H%M%S").to_string();
    let dir = out_dir.map(PathBuf::from).unwrap_or_else(default_export_dir);
    fs::create_dir_all(&dir)?;
    let fname = format!("hyrwbz_export_{}.xlsx", now);
    let path = dir.join(fname);
    wb.save(&path)?;
    Ok(ExportResult {
        path: path.to_string_lossy().to_string(),
        sheets: sheets_names,
    })
}

fn format_sheet_name(saved_at: &str) -> String {
    // saved_at 形如 "2026-08-31 23:45:12" -> "20260831_234512"
    let s = saved_at.replace(['-', ':', ' '], "");
    if s.len() >= 14 {
        format!("{}_{}", &s[..8], &s[8..14])
    } else {
        saved_at.to_string()
    }
}

fn write_sheet(
    sheet: &mut rust_xlsxwriter::Worksheet,
    tasks: &[Task],
    title_fmt: &Format,
    center: &Format,
) -> Result<()> {
    // 动态计算最大延期数
    let max_delays = tasks.iter().map(|t| t.delays.len()).max().unwrap_or(0);
    // 基础表头
    let base_headers = [
        "序号", "会议号", "任务号", "任务说明", "责任部门", "责任人",
        "要求完成时间", "实际完成时间",
    ];
    // 写基础表头
    for (c, h) in base_headers.iter().enumerate() {
        sheet.write_with_format(0, c as u16, *h, title_fmt)?;
    }
    // 动态延期表头：延期1/理由1, 延期2/理由2, ...
    let mut col = base_headers.len() as u16;
    for d in 0..max_delays {
        sheet.write_with_format(0, col, format!("延期{}", d + 1), title_fmt)?;
        col += 1;
        sheet.write_with_format(0, col, format!("理由{}", d + 1), title_fmt)?;
        col += 1;
    }
    // 最后是说明及备注
    let remark_col = col;
    sheet.write_with_format(0, remark_col, "说明及备注", title_fmt)?;

    // 写数据
    for (i, t) in tasks.iter().enumerate() {
        let r = (i + 1) as u32;
        let seq: u32 = (i + 1) as u32;
        sheet.write_with_format(r, 0, seq, center)?;
        sheet.write(r, 1, &t.meeting_no)?;
        sheet.write(r, 2, t.task_no)?;
        sheet.write(r, 3, &t.task_desc)?;
        sheet.write(r, 4, &t.dept)?;
        sheet.write(r, 5, &t.owner)?;
        sheet.write(r, 6, &t.required_date)?;
        sheet.write(r, 7, &t.actual_date)?;
        // 延期数据
        let mut c = 8u16;
        for d in 0..max_delays {
            if let Some(delay) = t.delays.get(d) {
                sheet.write(r, c, &delay.delay_date)?;
                sheet.write(r, c + 1, &delay.delay_reason)?;
            } else {
                sheet.write(r, c, "")?;
                sheet.write(r, c + 1, "")?;
            }
            c += 2;
        }
        sheet.write(r, remark_col, &t.remark)?;
    }
    // 列宽
    sheet.set_column_width(0, 6)?;
    sheet.set_column_width(1, 18)?;
    sheet.set_column_width(2, 8)?;
    sheet.set_column_width(3, 30)?;
    sheet.set_column_width(4, 14)?;
    sheet.set_column_width(5, 10)?;
    sheet.set_column_width(6, 14)?;
    sheet.set_column_width(7, 14)?;
    for cc in 8..remark_col {
        sheet.set_column_width(cc, 14)?;
    }
    sheet.set_column_width(remark_col, 30)?;
    Ok(())
}


fn default_export_dir() -> PathBuf {
    // 导出目录放在 exe 同目录下的 exports/（安装目录）
    let exe = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("."));
    let dir = exe.parent().unwrap_or_else(|| std::path::Path::new("."));
    dir.join("exports")
}
