-- 常用筛选、排序和通知扫描索引。
CREATE INDEX IF NOT EXISTS idx_tasks_meeting_task
    ON tasks(meeting_no, task_no);
CREATE INDEX IF NOT EXISTS idx_tasks_required_date
    ON tasks(required_date);
CREATE INDEX IF NOT EXISTS idx_tasks_actual_date
    ON tasks(actual_date);
CREATE INDEX IF NOT EXISTS idx_tasks_updated_at
    ON tasks(updated_at);
CREATE INDEX IF NOT EXISTS idx_delays_task_date
    ON delays(task_id, delay_date, id);
CREATE INDEX IF NOT EXISTS idx_attachments_task
    ON attachments(task_id, id);
