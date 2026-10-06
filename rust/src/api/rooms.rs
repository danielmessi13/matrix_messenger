use matrix_sdk::Room;

use crate::{api::client::MatrixClient, frb_generated::StreamSink};

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

impl MatrixClient {
    pub fn watch_rooms(&self, sink: StreamSink<Vec<RoomSummary>>) {
        self.rooms.watch_rooms(move |rooms| sink.add(rooms).is_ok());
    }

    pub fn watch_sync_status(&self, sink: StreamSink<SyncStatus>) {
        self.rooms
            .watch_status(move |status| sink.add(status).is_ok());
    }

    pub async fn accept_invite(&self, room_id: String) -> Result<(), InviteError> {
        Ok(self.invited_room(room_id)?.join().await?)
    }

    pub async fn decline_invite(&self, room_id: String) -> Result<(), InviteError> {
        Ok(self.invited_room(room_id)?.leave().await?)
    }

    fn invited_room(&self, room_id: String) -> Result<Room, InviteError> {
        self.find_room(&room_id).ok_or(InviteError {
            kind: InviteErrorKind::RoomNotFound,
            message: room_id,
        })
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use matrix_sdk::{ruma::room_id, test_utils::mocks::MatrixMockServer, RoomState};
    use matrix_sdk_test::InvitedRoomBuilder;

    use super::*;
    use crate::test_support::{env_var, offline_client, temp_data_dir};

    async fn client_with_invite(
        server: &MatrixMockServer,
        name: &str,
    ) -> (MatrixClient, Room) {
        let client = server.client_builder().build().await;
        let room = server
            .sync_room(&client, InvitedRoomBuilder::new(room_id!("!convite:example.org")))
            .await;
        (MatrixClient::new(client, temp_data_dir(name), None), room)
    }

    #[tokio::test]
    async fn accept_invite_joins_the_room() {
        let server = MatrixMockServer::new().await;
        let (client, room) = client_with_invite(&server, "accept_invite").await;
        server.mock_room_join(room.room_id()).ok().expect(1).mount().await;

        client.accept_invite(room.room_id().to_string()).await.unwrap();

        assert_eq!(room.state(), RoomState::Joined);
    }

    #[tokio::test]
    async fn decline_invite_leaves_and_forgets_the_room() {
        let server = MatrixMockServer::new().await;
        let (client, room) = client_with_invite(&server, "decline_invite").await;
        server.mock_room_leave().ok(room.room_id()).expect(1).mount().await;
        server.mock_room_forget().ok().expect(1).mount().await;

        client.decline_invite(room.room_id().to_string()).await.unwrap();

        assert!(client.find_room(room.room_id().as_str()).is_none());
    }

    #[tokio::test]
    async fn failed_accept_invite_is_network_error() {
        let server = MatrixMockServer::new().await;
        let (client, room) = client_with_invite(&server, "accept_invite_fails").await;
        server.mock_room_join(room.room_id()).error500().mount().await;

        let error = client.accept_invite(room.room_id().to_string()).await.unwrap_err();

        assert_eq!(error.kind, InviteErrorKind::Network);
        assert_eq!(room.state(), RoomState::Invited);
    }

    #[tokio::test]
    async fn invite_of_unknown_room_is_room_not_found() {
        let store_path = std::path::PathBuf::from(temp_data_dir("invite_unknown")).join("store");
        let client = MatrixClient::new(
            offline_client(&store_path).await,
            temp_data_dir("invite_unknown_data"),
            None,
        );

        for room_id in ["!naoexiste:b.c", "isto não é um id"] {
            let accept = client.accept_invite(room_id.to_owned()).await.unwrap_err();
            let decline = client.decline_invite(room_id.to_owned()).await.unwrap_err();
            assert_eq!(accept.kind, InviteErrorKind::RoomNotFound, "{room_id}");
            assert_eq!(decline.kind, InviteErrorKind::RoomNotFound, "{room_id}");
        }
    }

    /// Requer MATRIX_HOMESERVER, MATRIX_USERNAME e MATRIX_PASSWORD.
    #[tokio::test]
    #[ignore]
    async fn room_sync_with_real_account() {
        let client = MatrixClient::login(
            env_var("MATRIX_HOMESERVER"),
            env_var("MATRIX_USERNAME"),
            env_var("MATRIX_PASSWORD"),
            temp_data_dir("real_rooms"),
        )
        .await
        .unwrap_or_else(|e| panic!("login falhou: {:?} - {}", e.kind, e.message));
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        client
            .room_sync()
            .watch_rooms(move |rooms| tx.send(rooms).is_ok());

        let rooms = tokio::time::timeout(Duration::from_secs(60), rx.recv())
            .await
            .expect("lista em até 60 s")
            .expect("sync encerrado");
        println!("{} salas", rooms.len());

        client
            .logout()
            .await
            .unwrap_or_else(|e| panic!("logout falhou: {}", e.message));
    }
}
