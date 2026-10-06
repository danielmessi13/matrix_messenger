#[derive(Debug, Clone, PartialEq)]
pub struct TimelineSnapshot {
    pub items: Vec<TimelineEntry>,
    pub reached_start: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TimelineEntry {
    pub date_divider_ms: Option<i64>,
    pub message: Option<TimelineMessage>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TimelineMessage {
    pub id: String,
    pub sender_id: String,
    pub sender_name: String,
    pub is_own: bool,
    pub timestamp_ms: i64,
    pub kind: MessageKind,
    pub body: Option<String>,
    pub edited: bool,
    pub send_state: SendState,
    pub thread: Option<ThreadInfo>,
    pub reply_to: Option<ReplyPreview>,
    pub read_by: Vec<String>,
}

// Remetente, tipo e texto só vêm em `Ready`.
#[derive(Debug, Clone, PartialEq)]
pub struct ReplyPreview {
    pub state: ReplyState,
    pub sender_name: Option<String>,
    pub kind: Option<MessageKind>,
    pub body: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ReplyState {
    Loading,
    Ready,
    Unavailable,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ThreadInfo {
    pub root_event_id: String,
    pub replies: u32,
    pub latest_sender: Option<String>,
    pub latest_timestamp_ms: Option<i64>,
    pub unread: u32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MessageKind {
    Text,
    Notice,
    Emote,
    Image,
    File,
    Encrypted,
    Redacted,
    Other,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SendState {
    Sent,
    Sending,
    Failed,
    Rejected,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TimelineErrorKind {
    RoomNotFound,
    MessageNotFound,
    Network,
    Unknown,
}

#[derive(Debug)]
pub struct TimelineError {
    pub kind: TimelineErrorKind,
    pub message: String,
}

impl TimelineError {
    pub(crate) fn new(kind: TimelineErrorKind, message: String) -> Self {
        Self { kind, message }
    }

    fn from_sdk(error: &matrix_sdk::Error) -> Self {
        let kind = match error {
            matrix_sdk::Error::Http(_) => TimelineErrorKind::Network,
            _ => TimelineErrorKind::Unknown,
        };
        Self::new(kind, error.to_string())
    }
}

impl From<matrix_sdk_ui::timeline::Error> for TimelineError {
    fn from(error: matrix_sdk_ui::timeline::Error) -> Self {
        use matrix_sdk_ui::timeline::Error;
        let kind = match &error {
            Error::Sdk(error) => return Self::from_sdk(error),
            Error::PaginationError(_) => TimelineErrorKind::Network,
            _ => TimelineErrorKind::Unknown,
        };
        Self::new(kind, error.to_string())
    }
}

impl From<matrix_sdk::Error> for TimelineError {
    fn from(error: matrix_sdk::Error) -> Self {
        Self::from_sdk(&error)
    }
}

use std::mem::ManuallyDrop;

use flutter_rust_bridge::frb;
use tokio::runtime::Handle;

use crate::{frb_generated::StreamSink, timeline::TimelineHandle};

#[frb(opaque)]
pub struct RoomTimeline {
    pub(crate) handle: ManuallyDrop<TimelineHandle>,
    runtime: Handle,
}

impl Drop for RoomTimeline {
    /// O finalizer do Dart roda fora do runtime Tokio, e a Timeline guarda clones do Client.
    fn drop(&mut self) {
        let _guard = self.runtime.enter();
        // SAFETY: `handle` não é mais acessado depois daqui; o próprio `RoomTimeline` está sendo destruído.
        unsafe { ManuallyDrop::drop(&mut self.handle) };
    }
}

impl RoomTimeline {
    pub(crate) fn new(handle: TimelineHandle) -> Self {
        Self { handle: ManuallyDrop::new(handle), runtime: Handle::current() }
    }

    pub fn watch(&self, sink: StreamSink<TimelineSnapshot>) {
        self.handle.watch(move |snapshot| sink.add(snapshot).is_ok());
    }

    pub async fn paginate_backwards(&self) -> Result<bool, TimelineError> {
        self.handle.paginate_backwards().await
    }

    pub async fn send_markdown(&self, body: String) -> Result<(), TimelineError> {
        self.handle.send_markdown(body).await
    }

    pub async fn retry(&self, item_id: String) -> Result<(), TimelineError> {
        self.handle.retry(&item_id).await
    }

    pub async fn cancel(&self, item_id: String) -> Result<(), TimelineError> {
        self.handle.cancel(&item_id).await
    }

    pub async fn mark_as_read(&self) -> Result<(), TimelineError> {
        self.handle.mark_as_read().await
    }

    pub async fn open_thread(&self, root_event_id: String) -> Result<RoomTimeline, TimelineError> {
        Ok(Self::new(self.handle.open_thread(&root_event_id).await?))
    }
}
