# -*- coding: utf-8 -*-
"""生成 5000 条 HYRWBZ 导入/导出回归测试数据（仅依赖 Python 标准库）。
默认输出 CSV、标准 XLSX、完整 SQLite 数据库、全量 ZIP 和 manifest.json。
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import random
import shutil
import sqlite3
import zipfile
from datetime import date, timedelta
from pathlib import Path
from xml.sax.saxutils import escape as xml_escape

HEADERS = ["序号", "会议纪要号", "任务序号", "任务内容", "责任部门", "责任人",
           "计划完成时间", "延期时间", "实际完成时间", "备注"]
DEPTS = ["工程部", "技术部", "质量安全部", "物资部", "综合办公室", "计划经营部", "财务部"]
OWNERS = ["张伟", "李强", "王芳", "刘洋", "陈静", "赵磊", "孙敏", "周涛", "吴丽", "郑军"]
TOPICS = ["一号楼", "地下车库", "东侧基坑", "2#生产线", "配电室", "消防泵房", "屋面防水", "外幕墙", "厂区道路", "污水处理站", "综合管廊", "成品仓库"]
TASK_TEMPLATES = ["完成{}区域主体结构施工", "组织{}设备进场安装调试", "提交{}分项工程验收资料", "完成{}系统联调测试", "整改{}部位质量问题并复检", "编制{}专项施工方案并报审", "完成{}材料进场报验", "落实{}区域安全防护措施", "更新{}进度计划并上报", "协调{}专业交叉施工安排"]
REMARKS = ["", "", "已提前完成", "受雨天影响", "待验收", "需要重点跟进，包含逗号,用于 CSV 转义", "中文逗号，和顿号、用于自动转换"]
DB_SCHEMA = """
PRAGMA foreign_keys = ON;
CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, meeting_no TEXT NOT NULL, task_no INTEGER NOT NULL, task_desc TEXT NOT NULL DEFAULT '', dept TEXT NOT NULL DEFAULT '', owner TEXT NOT NULL DEFAULT '', required_date TEXT NOT NULL DEFAULT '', actual_date TEXT NOT NULL DEFAULT '', remark TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')), UNIQUE(meeting_no, task_no));
CREATE TABLE delays (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL, meeting_no TEXT NOT NULL, task_no INTEGER NOT NULL, delay_date TEXT NOT NULL, delay_reason TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT (datetime('now')), FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE);
CREATE INDEX idx_delays_task_id ON delays(task_id); CREATE INDEX idx_delays_meeting_task ON delays(meeting_no, task_no);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL DEFAULT '');
CREATE TABLE snapshots (snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT, saved_at TEXT NOT NULL DEFAULT (datetime('now')), remark TEXT NOT NULL DEFAULT '', payload TEXT NOT NULL); CREATE INDEX idx_snapshots_saved_at ON snapshots(saved_at);
CREATE TABLE attachments (id INTEGER PRIMARY KEY AUTOINCREMENT, task_id INTEGER NOT NULL, filename TEXT NOT NULL, stored_name TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')), FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE); CREATE INDEX idx_attachments_task_id ON attachments(task_id);
"""

def parse_args():
    parser = argparse.ArgumentParser(description="生成 HYRWBZ 5000 条导入/导出测试数据")
    parser.add_argument("--count", type=int, default=5000, help="任务条数，默认 5000，最大 5000")
    parser.add_argument("--output-dir", type=Path, default=Path("test-fixtures-5000"))
    parser.add_argument("--seed", type=int, default=20260903)
    parser.add_argument("--clean", action="store_true", help="覆盖已有输出目录")
    return parser.parse_args()

def fmt(value):
    return value.strftime("%Y/%m/%d")

def safe(value):
    return "".join("_" if char in '/\\:*?"<>|' else char for char in value)

def make_data(count, rng):
    tasks, delays, attachments = [], [], []
    base, delay_id, attachment_id = date(2026, 9, 3), 1, 1
    for task_id in range(1, count + 1):
        meeting = f"纪要〔2026〕{(task_id - 1) // 20 + 1}号"
        task_no = (task_id - 1) % 20 + 1
        required = base + timedelta(days=rng.randint(-120, 240))
        task = {"id": task_id, "meeting_no": meeting, "task_no": task_no,
                "task_desc": rng.choice(TASK_TEMPLATES).format(rng.choice(TOPICS)),
                "dept": rng.choice(DEPTS), "owner": rng.choice(OWNERS),
                "required_date": fmt(required), "actual_date": "", "remark": rng.choice(REMARKS),
                "created_at": "2026-09-03 08:00:00",
                "updated_at": f"2026-09-03 {task_id % 24:02d}:{task_id % 60:02d}:00",
                "has_attachment": False, "delays": []}
        status = task_id % 10
        if status <= 5:
            task["actual_date"] = fmt(required + timedelta(days=rng.randint(-5, 5)))
        elif status == 6:
            task["actual_date"] = "进行中"
        elif status == 7:
            task["actual_date"] = "待确认"
        if task_id % 17 == 0:
            task["dept"] = "工程部，技术部、质量安全部"
        elif task_id % 23 == 0:
            task["dept"] = "物资部,综合办公室"
        if task_id % 19 == 0:
            task["owner"] = "张伟，李强、王芳"
        elif task_id % 29 == 0:
            task["owner"] = "刘洋,陈静"
        if task_id % 4 == 0:
            delay_date = required + timedelta(days=rng.randint(3, 25))
            delay = {"id": delay_id, "task_id": task_id, "meeting_no": meeting, "task_no": task_no,
                     "delay_date": fmt(delay_date), "delay_reason": "等待材料，需协调相关部门", "created_at": "2026-09-03 09:00:00"}
            delay_id += 1; task["delays"].append(delay); delays.append(delay)
            if task_id % 25 == 0:
                second = dict(delay, id=delay_id, delay_date=fmt(delay_date + timedelta(days=7)), delay_reason="现场条件变化，重新安排计划")
                delay_id += 1; task["delays"].append(second); delays.append(second)
        if task_id % 10 == 0:
            filename = f"附件_{task_id:04d}.txt"
            stored = f"{safe(meeting)}/{task_no}/fixture_{task_id:05d}_{filename}"
            attachments.append({"id": attachment_id, "task_id": task_id, "filename": filename, "stored_name": stored, "created_at": "2026-09-03 10:00:00"})
            attachment_id += 1; task["has_attachment"] = True
        tasks.append(task)
    return tasks, delays, attachments

def csv_row(task):
    return [task["id"], task["meeting_no"], task["task_no"], task["task_desc"], task["dept"], task["owner"], task["required_date"], task["delays"][0]["delay_date"] if task["delays"] else "", task["actual_date"], task["remark"]]

def write_csv(path, tasks):
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle); writer.writerow(HEADERS); writer.writerows(csv_row(task) for task in tasks)

def excel_col(index):
    result = ""; index += 1
    while index:
        index, remainder = divmod(index - 1, 26); result = chr(65 + remainder) + result
    return result

def xlsx_cell(row, column, value):
    ref = f"{excel_col(column)}{row}"
    if isinstance(value, int): return f'<c r="{ref}"><v>{value}</v></c>'
    return f'<c r="{ref}" t="inlineStr"><is><t>{xml_escape(str(value))}</t></is></c>'
def write_xlsx(path, tasks):
    rows = [HEADERS] + [csv_row(task) for task in tasks]
    xml_rows = []
    for row_number, values in enumerate(rows, 1):
        xml_rows.append(f'<row r="{row_number}">' + ''.join(xlsx_cell(row_number, col, value) for col, value in enumerate(values)) + '</row>')
    sheet = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
             '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
             f'<dimension ref="A1:J{len(rows)}"/><sheetData>{"".join(xml_rows)}</sheetData></worksheet>')
    files = {
        "[Content_Types].xml": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'),
        "_rels/.rels": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
        "xl/workbook.xml": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="当前数据" sheetId="1" r:id="rId1"/></sheets></workbook>'),
        "xl/_rels/workbook.xml.rels": ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'),
        "xl/worksheets/sheet1.xml": sheet,
    }
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in files.items(): archive.writestr(name, content.encode("utf-8"))

def payload(task):
    return {key: task[key] for key in ("id", "meeting_no", "task_no", "task_desc", "dept", "owner", "required_date", "actual_date", "remark", "created_at", "updated_at", "has_attachment", "delays")}

def write_db(path, tasks, delays, attachments):
    connection = sqlite3.connect(path); connection.executescript(DB_SCHEMA)
    connection.executemany("INSERT INTO tasks (id,meeting_no,task_no,task_desc,dept,owner,required_date,actual_date,remark,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
      [(t["id"], t["meeting_no"], t["task_no"], t["task_desc"], t["dept"], t["owner"], t["required_date"], t["actual_date"], t["remark"], t["created_at"], t["updated_at"]) for t in tasks])
    connection.executemany("INSERT INTO delays (id,task_id,meeting_no,task_no,delay_date,delay_reason,created_at) VALUES (?,?,?,?,?,?,?)",
      [(d["id"], d["task_id"], d["meeting_no"], d["task_no"], d["delay_date"], d["delay_reason"], d["created_at"]) for d in delays])
    connection.execute("INSERT INTO meta(key,value) VALUES ('locked_meeting_no',?)", (tasks[0]["meeting_no"],))
    payload_json = json.dumps([payload(t) for t in tasks], ensure_ascii=False, separators=(",", ":"))
    connection.execute("INSERT INTO snapshots(saved_at,remark,payload) VALUES (?,?,?)", ("2026-09-03 12:00:00", "5000条导入导出回归测试", payload_json))
    connection.executemany("INSERT INTO attachments (id,task_id,filename,stored_name,created_at) VALUES (?,?,?,?,?)",
      [(a["id"], a["task_id"], a["filename"], a["stored_name"], a["created_at"]) for a in attachments])
    connection.execute("PRAGMA optimize"); connection.commit(); connection.close()

def write_zip(path, database, attachments):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.write(database, "data.db"); archive.writestr("attachments/", b"")
        for attachment in attachments:
            content = f"HYRWBZ fixture attachment\ntask_id={attachment['task_id']}\nfilename={attachment['filename']}\n"
            archive.writestr(f"attachments/{attachment['stored_name']}", content.encode("utf-8"))

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""): digest.update(chunk)
    return digest.hexdigest()

def write_manifest(path, seed, count, tasks, delays, attachments, files):
    coverage = {
        "xlsx_import": True,
        "csv_import_with_utf8_bom": True,
        "database_import": True,
        "all_files_import_with_attachments": True,
        "completed_actual_dates": sum("/" in t["actual_date"] for t in tasks),
        "in_progress_actual_dates": sum(t["actual_date"] == "进行中" for t in tasks),
        "non_date_actual_statuses": sum(t["actual_date"] not in ("", "进行中") and "/" not in t["actual_date"] for t in tasks),
        "empty_actual_dates": sum(not t["actual_date"] for t in tasks),
        "tasks_with_multiple_delays": sum(len(t["delays"]) > 1 for t in tasks),
        "mixed_comma_departments": sum("，" in t["dept"] or "、" in t["dept"] for t in tasks),
        "mixed_comma_owners": sum("，" in t["owner"] or "、" in t["owner"] for t in tasks),
    }
    result = {"generator": "scripts/gen_test_xls.py", "seed": seed, "task_count": count,
              "delay_count": len(delays), "attachment_count": len(attachments),
              "database_tables": ["tasks", "delays", "meta", "snapshots", "attachments"],
              "coverage": coverage,
              "files": {file.name: {"bytes": file.stat().st_size, "sha256": sha256(file)} for file in files}}
    path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    options = parse_args()
    if not 1 <= options.count <= 5000:
        raise SystemExit("--count 必须在 1 到 5000 之间")
    if options.output_dir.exists():
        if not options.clean:
            raise SystemExit(f"输出目录已存在，请使用 --clean 覆盖: {options.output_dir}")
        shutil.rmtree(options.output_dir)
    options.output_dir.mkdir(parents=True)
    tasks, delays, attachments = make_data(options.count, random.Random(options.seed))
    csv_path = options.output_dir / f"tasks_{options.count}.csv"
    xlsx_path = options.output_dir / f"tasks_{options.count}.xlsx"
    db_path = options.output_dir / f"data_{options.count}.db"
    zip_path = options.output_dir / f"hyrwbz_all_files_{options.count}.zip"
    write_csv(csv_path, tasks)
    write_xlsx(xlsx_path, tasks)
    write_db(db_path, tasks, delays, attachments)
    write_zip(zip_path, db_path, attachments)
    manifest_path = options.output_dir / "manifest.json"
    write_manifest(manifest_path, options.seed, options.count, tasks, delays, attachments, [csv_path, xlsx_path, db_path, zip_path])
    print(f"已生成 {options.count} 条任务；延期 {len(delays)} 条；附件 {len(attachments)} 个")
    for path in (csv_path, xlsx_path, db_path, zip_path, manifest_path):
        print(path)


if __name__ == "__main__":
    main()
