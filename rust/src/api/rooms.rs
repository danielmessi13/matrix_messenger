#[derive(Debug, Clone, PartialEq)]
pub struct RoomSummary {
    pub id: String,
    pub name: String,
    pub is_direct: bool,
    pub is_invite: bool,
    pub unread_messages: u32,
    pub unread_mentions: u32,
    pub unread_thread_replies: u32,
    pub member_count: u32,
    pub heroes: Vec<String>,
    pub latest: Option<LatestMessage>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct LatestMessage {
    pub sender_name: String,
    pub is_own: bool,
    pub kind: LatestMessageKind,
    pub body: Option<String>,
    pub timestamp_ms: i64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LatestMessageKind {
    Text,
    Image,
    File,
    Encrypted,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SyncStatus {
    Connecting,
    Running,
    Offline,
    Unsupported,
    Error,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum InviteErrorKind {
    RoomNotFound,
    Network,
    Unknown,
}

#[derive(Debug)]
pub struct InviteError {
    pub kind: InviteErrorKind,
    pub message: String,
}

impl From<matrix_sdk::Error> for InviteError {
    fn from(error: matrix_sdk::Error) -> Self {
        let kind = match error {
            matrix_sdk::Error::Http(_) => InviteErrorKind::Network,
            _ => InviteErrorKind::Unknown,
        };
        Self {
            kind,
            message: error.to_string(),
        }
    }
}
