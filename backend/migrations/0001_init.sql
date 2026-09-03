-- 任务表
CREATE TABLE IF NOT EXISTS tasks (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    meeting_no   TEXT    NOT NULL,
    task_no      INTEGER NOT NULL,
    task_desc    TEXT    NOT NULL DEFAULT '',
    dept         TEXT    NOT NULL DEFAULT '',
    owner        TEXT    NOT NULL DEFAULT '',
    required_date TEXT   NOT NULL DEFAULT '',
    actual_date  TEXT    NOT NULL DEFAULT '',
    remark       TEXT    NOT NULL DEFAULT '',
    created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE(meeting_no, task_no)
);

-- 延期表：每个 task_id 最多 20 条，业务层保证滚动
CREATE TABLE IF NOT EXISTS delays (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id      INTEGER NOT NULL,
    meeting_no   TEXT    NOT NULL,
    task_no      INTEGER NOT NULL,
    delay_date   TEXT    NOT NULL,
    delay_reason TEXT    NOT NULL DEFAULT '',
    created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_delays_task_id ON delays(task_id);
CREATE INDEX IF NOT EXISTS idx_delays_meeting_task ON delays(meeting_no, task_no);

-- 元信息表（持久化会议号锁定等）
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL DEFAULT ''
);

-- 历史快照表：最多保留 10 份
CREATE TABLE IF NOT EXISTS snapshots (
    snapshot_id INTEGER PRIMARY KEY AUTOINCREMENT,
    saved_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    remark      TEXT    NOT NULL DEFAULT '',
    payload     TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_snapshots_saved_at ON snapshots(saved_at);

-- 附件表
CREATE TABLE IF NOT EXISTS attachments (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id      INTEGER NOT NULL,
    filename     TEXT    NOT NULL,
    stored_name  TEXT    NOT NULL,
    created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_attachments_task_id ON attachments(task_id);
