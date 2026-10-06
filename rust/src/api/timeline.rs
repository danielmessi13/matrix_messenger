#[derive(Debug, Clone, PartialEq)]
pub struct TimelineSnapshot {
    pub items: Vec<TimelineEntry>,
    pub reached_start: bool,
    // Vem do status de paginação do SDK; sempre false na thread.
    pub paginating: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TimelineEntry {
    pub date_divider_ms: Option<i64>,
    pub message: Option<TimelineMessage>,
    pub room_event: Option<RoomEvent>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RoomEvent {
    pub id: String,
    pub sender_name: String,
    pub is_own: bool,
    pub timestamp_ms: i64,
    pub kind: RoomEventKind,
    pub target_name: Option<String>,
    pub target_is_own: bool,
    pub value: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum RoomEventKind {
    Created,
    Joined,
    Left,
    Invited,
    InviteDeclined,
    Kicked,
    Banned,
    Unbanned,
    NameChanged,
    TopicChanged,
    AvatarChanged,
    EncryptionEnabled,
    DisplayNameChanged,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TimelineMessage {
    pub id: String,
    // O `id` é o da timeline; responder, abrir thread e ir até a citação usam o do evento, que o eco local ainda não tem.
    pub event_id: Option<String>,
    pub sender_id: String,
    pub sender_name: String,
    pub is_own: bool,
    pub timestamp_ms: i64,
    pub kind: MessageKind,
    pub body: Option<String>,
    pub edited: bool,
    pub send_state: SendState,
    pub can_reply: bool,
    pub thread: Option<ThreadInfo>,
    pub reply_to: Option<ReplyPreview>,
    pub read_by: Vec<String>,
    pub image: Option<ImageContent>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ImageContent {
    pub filename: String,
    pub caption: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub mimetype: Option<String>,
    pub media: String,
}

// Remetente, tipo e texto só vêm em `Ready`.
#[derive(Debug, Clone, PartialEq)]
pub struct ReplyPreview {
    pub event_id: String,
    pub state: ReplyState,
    pub is_own: bool,
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
    InvalidImage,
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

use crate::{api::client::MatrixClient, frb_generated::StreamSink, timeline::TimelineHandle};

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
        Self {
            handle: ManuallyDrop::new(handle),
            runtime: Handle::current(),
        }
    }

    pub fn watch(&self, sink: StreamSink<TimelineSnapshot>) {
        self.handle
            .watch(move |snapshot| sink.add(snapshot).is_ok());
    }

    pub async fn paginate_backwards(&self) -> Result<bool, TimelineError> {
        self.handle.paginate_backwards().await
    }

    pub async fn send_markdown(&self, body: String) -> Result<(), TimelineError> {
        self.handle.send_markdown(body).await
    }

    pub async fn send_reply(&self, body: String, in_reply_to: String) -> Result<(), TimelineError> {
        self.handle.send_reply(body, &in_reply_to).await
    }

    pub async fn send_image(
        &self,
        path: String,
        in_reply_to: Option<String>,
    ) -> Result<(), TimelineError> {
        self.handle.send_image(&path, in_reply_to.as_deref()).await
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

    pub fn watch_typing(&self, sink: StreamSink<Vec<String>>) {
        self.handle
            .watch_typing(move |names| sink.add(names).is_ok());
    }

    pub async fn set_typing(&self, typing: bool) -> Result<(), TimelineError> {
        self.handle.set_typing(typing).await
    }

    pub async fn open_thread(&self, root_event_id: String) -> Result<RoomTimeline, TimelineError> {
        Ok(Self::new(self.handle.open_thread(&root_event_id).await?))
    }
}

impl MatrixClient {
    pub async fn open_timeline(&self, room_id: String) -> Result<RoomTimeline, TimelineError> {
        let room = self
            .find_room(&room_id)
            .ok_or_else(|| TimelineError::new(TimelineErrorKind::RoomNotFound, room_id))?;
        let handle =
            TimelineHandle::open(room, None, self.thread_reads.clone(), self.runtime.clone())
                .await?;
        Ok(RoomTimeline::new(handle))
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::*;
    use crate::test_support::{env_var, offline_client, temp_data_dir};

    #[tokio::test]
    async fn open_timeline_of_unknown_room_is_room_not_found() {
        let store_path = std::path::PathBuf::from(temp_data_dir("timeline_unknown")).join("store");
        let client = MatrixClient::new(
            offline_client(&store_path).await,
            temp_data_dir("timeline_unknown_data"),
            None,
        );

        for room_id in ["!naoexiste:b.c", "isto não é um id"] {
            let error = client
                .open_timeline(room_id.to_owned())
                .await
                .err()
                .unwrap();
            assert_eq!(error.kind, TimelineErrorKind::RoomNotFound, "{room_id}");
        }
    }

    /// Requer MATRIX_HOMESERVER, MATRIX_USERNAME e MATRIX_PASSWORD e uma sala na conta.
    #[tokio::test]
    #[ignore]
    async fn timeline_send_with_real_account() {
        let client = MatrixClient::login(
            env_var("MATRIX_HOMESERVER"),
            env_var("MATRIX_USERNAME"),
            env_var("MATRIX_PASSWORD"),
            temp_data_dir("real_timeline"),
        )
        .await
        .unwrap_or_else(|e| panic!("login falhou: {:?} - {}", e.kind, e.message));
        let (rooms_tx, mut rooms_rx) = tokio::sync::mpsc::unbounded_channel();
        client
            .room_sync()
            .watch_rooms(move |rooms| rooms_tx.send(rooms).is_ok());
        let rooms = tokio::time::timeout(Duration::from_secs(60), rooms_rx.recv())
            .await
            .expect("lista em até 60 s")
            .expect("sync encerrado");
        let room = rooms
            .iter()
            .find(|room| !room.is_invite)
            .expect("uma sala na conta");

        let timeline = client.open_timeline(room.id.clone()).await.unwrap();
        timeline
            .handle
            .send_markdown("teste do **matrix_messenger**".to_owned())
            .await
            .unwrap();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        timeline
            .handle
            .watch(move |snapshot| tx.send(snapshot).is_ok());
        loop {
            let snapshot = tokio::time::timeout(Duration::from_secs(30), rx.recv())
                .await
                .expect("snapshot em até 30 s")
                .expect("timeline encerrada");
            let sent = snapshot
                .items
                .iter()
                .filter_map(|entry| entry.message.as_ref())
                .any(|m| {
                    m.is_own
                        && m.send_state == SendState::Sent
                        && m.body.as_deref() == Some("teste do **matrix_messenger**")
                });
            if sent {
                break;
            }
        }

        drop(timeline);
        client
            .logout()
            .await
            .unwrap_or_else(|e| panic!("logout falhou: {}", e.message));
    }
}
