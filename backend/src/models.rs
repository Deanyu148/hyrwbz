use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Task {
    pub id: i64,
    pub meeting_no: String,
    pub task_no: i64,
    pub task_desc: String,
    pub dept: String,
    pub owner: String,
    pub required_date: String,
    pub actual_date: String,
    pub remark: String,
    pub created_at: String,
    pub updated_at: String,
    #[serde(default)]
    pub has_attachment: bool,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub delays: Vec<Delay>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Delay {
    pub id: i64,
    pub task_id: i64,
    pub meeting_no: String,
    pub task_no: i64,
    pub delay_date: String,
    pub delay_reason: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateTaskReq {
    pub meeting_no: String,
    pub task_desc: String,
    pub dept: String,
    pub owner: String,
    pub required_date: String,
    pub actual_date: String,
    pub remark: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct UpdateTaskReq {
    pub meeting_no: String,
    pub task_no: i64,
    pub task_desc: String,
    pub dept: String,
    pub owner: String,
    pub required_date: String,
    pub actual_date: String,
    pub remark: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct CreateDelayReq {
    pub delay_date: String,
    pub delay_reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LockedMeeting {
    pub meeting_no: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SetLockedMeetingReq {
    pub meeting_no: Option<String>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct FilterReq {
    pub meeting_no: Option<String>,
    pub task_no: Option<i64>,
    pub dept: Option<String>,
    pub owner: Option<String>,
    pub required_date_from: Option<String>,
    pub required_date_to: Option<String>,
    pub actual_date_from: Option<String>,
    pub actual_date_to: Option<String>,
    pub delay_date_from: Option<String>,
    pub delay_date_to: Option<String>,
    pub delay_index: Option<i64>,
    pub expected_remaining_days: Option<i64>,
    pub has_attachment: Option<bool>,
}

#[derive(Debug, Clone, Deserialize, Default)]
pub struct CreateSnapshotReq {
    pub remark: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct SnapshotInfo {
    pub snapshot_id: i64,
    pub saved_at: String,
    pub remark: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct SnapshotCreateResult {
    pub snapshot_id: i64,
    pub used_count: i64,
}

#[derive(Debug, Clone, Serialize)]
pub struct SnapshotDetail {
    pub snapshot_id: i64,
    pub saved_at: String,
    pub remark: String,
    pub tasks: Vec<Task>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ExportResult {
    pub path: String,
    pub sheets: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attachment {
    pub id: i64,
    pub task_id: i64,
    pub filename: String,
    pub stored_name: String,
    pub created_at: String,
}
