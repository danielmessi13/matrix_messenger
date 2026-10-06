use std::time::Duration;

use matrix_sdk::{
    ruma::{
        api::error::ErrorKind, matrix_uri::MatrixId, MatrixToUri, MatrixUri, OwnedRoomOrAliasId,
        OwnedServerName, RoomOrAliasId,
    },
    Room,
};

use crate::{api::client::MatrixClient, frb_generated::StreamSink};

#[derive(Debug, Clone, PartialEq)]
pub struct RoomSummary {
    pub id: String,
    pub name: String,
    pub is_direct: bool,
    pub is_invite: bool,
    pub is_public: bool,
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

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum JoinRoomErrorKind {
    InvalidLink,
    NotFound,
    Forbidden,
    Network,
    Unknown,
}

#[derive(Debug)]
pub struct JoinRoomError {
    pub kind: JoinRoomErrorKind,
    pub message: String,
}

impl From<matrix_sdk::Error> for JoinRoomError {
    fn from(error: matrix_sdk::Error) -> Self {
        let not_found_status = error
            .as_client_api_error()
            .is_some_and(|e| e.status_code.as_u16() == 404);
        let kind = match error.client_api_error_kind() {
            Some(ErrorKind::NotFound) => JoinRoomErrorKind::NotFound,
            Some(ErrorKind::Forbidden) => JoinRoomErrorKind::Forbidden,
            // Alguns servidores respondem 404 sem um errcode conhecido.
            _ if not_found_status => JoinRoomErrorKind::NotFound,
            None if matches!(error, matrix_sdk::Error::Http(_)) => JoinRoomErrorKind::Network,
            _ => JoinRoomErrorKind::Unknown,
        };
        Self {
            kind,
            message: error.to_string(),
        }
    }
}

fn parse_join_target(text: &str) -> Option<(OwnedRoomOrAliasId, Vec<OwnedServerName>)> {
    let text = text.trim();
    let (id, via) = if text.starts_with("https://matrix.to/") {
        let uri = MatrixToUri::parse(text).ok()?;
        (uri.id().clone(), uri.via().to_vec())
    } else if text.starts_with("matrix:") {
        let uri = MatrixUri::parse(text).ok()?;
        (uri.id().clone(), uri.via().to_vec())
    } else {
        return Some(with_server_of_id(
            RoomOrAliasId::parse(text).ok()?,
            Vec::new(),
        ));
    };
    let target: OwnedRoomOrAliasId = match id {
        MatrixId::Room(room_id) => room_id.into(),
        MatrixId::RoomAlias(alias) => alias.into(),
        _ => return None,
    };
    Some(with_server_of_id(target, via))
}

// Sem via o servidor não sabe por onde buscar uma sala de outro servidor.
fn with_server_of_id(
    target: OwnedRoomOrAliasId,
    mut via: Vec<OwnedServerName>,
) -> (OwnedRoomOrAliasId, Vec<OwnedServerName>) {
    if via.is_empty() && target.is_room_id() {
        if let Some(server) = target.server_name() {
            via.push(server.to_owned());
        }
    }
    (target, via)
}

// O retry padrão do SDK insiste por até 15 min em 5xx/429 e travaria o diálogo esperando.
const ROOM_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

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

    pub async fn room_link(&self, room_id: String) -> Option<String> {
        let room = self.find_room(&room_id)?;
        room.matrix_to_permalink()
            .await
            .ok()
            .map(|uri| uri.to_string())
    }

    pub async fn join_room(&self, target: String) -> Result<String, JoinRoomError> {
        self.join_room_within(&target, ROOM_REQUEST_TIMEOUT).await
    }

    async fn join_room_within(
        &self,
        target: &str,
        limit: Duration,
    ) -> Result<String, JoinRoomError> {
        let (room, via) = parse_join_target(target).ok_or_else(|| JoinRoomError {
            kind: JoinRoomErrorKind::InvalidLink,
            message: target.to_owned(),
        })?;
        let joined = tokio::time::timeout(limit, self.client.join_room_by_id_or_alias(&room, &via))
            .await
            .map_err(|_| JoinRoomError {
                kind: JoinRoomErrorKind::Network,
                message: format!("sem resposta do servidor em {limit:?}"),
            })??;
        Ok(joined.room_id().to_string())
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

    use matrix_sdk::{
        ruma::{room_id, user_id},
        test_utils::mocks::MatrixMockServer,
        RoomState,
    };
    use matrix_sdk_test::{event_factory::EventFactory, InvitedRoomBuilder, JoinedRoomBuilder};
    use serde_json::json;
    use wiremock::{
        matchers::{method, path_regex},
        Mock, ResponseTemplate,
    };

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

    async fn created_client(server: &MatrixMockServer, name: &str) -> MatrixClient {
        MatrixClient::new(
            server.client_builder().build().await,
            temp_data_dir(name),
            None,
        )
    }

    fn api_error(status: u16, errcode: &str) -> ResponseTemplate {
        ResponseTemplate::new(status).set_body_json(json!({ "errcode": errcode, "error": "x" }))
    }

    #[test]
    fn parse_join_target_accepts_room_links_ids_and_aliases() {
        let cases = [
            (
                "https://matrix.to/#/!abc:example.org?via=example.org&via=other.org",
                "!abc:example.org",
                vec!["example.org", "other.org"],
            ),
            (
                "https://matrix.to/#/%23sala:example.org",
                "#sala:example.org",
                vec![],
            ),
            (
                "https://matrix.to/#/#sala:example.org",
                "#sala:example.org",
                vec![],
            ),
            (
                "matrix:roomid/abc:example.org?via=other.org",
                "!abc:example.org",
                vec!["other.org"],
            ),
            ("matrix:r/sala:example.org", "#sala:example.org", vec![]),
            (
                "  !abc:example.org \n",
                "!abc:example.org",
                vec!["example.org"],
            ),
            ("#sala:example.org", "#sala:example.org", vec![]),
            (
                "!31hneApxJ_1o-63DmFrpeqnkFfWppnzWso1JvH3ogLM",
                "!31hneApxJ_1o-63DmFrpeqnkFfWppnzWso1JvH3ogLM",
                vec![],
            ),
        ];
        for (input, id, via) in cases {
            let (target, servers) =
                parse_join_target(input).unwrap_or_else(|| panic!("deveria aceitar {input:?}"));
            assert_eq!(target.as_str(), id, "{input}");
            let servers: Vec<&str> = servers.iter().map(|server| server.as_str()).collect();
            assert_eq!(servers, via, "{input}");
        }
    }

    #[test]
    fn parse_join_target_rejects_anything_else() {
        for input in [
            "",
            "   ",
            "qualquer coisa",
            "@ana:example.org",
            "https://matrix.to/#/@ana:example.org",
            "https://matrix.to/#/!abc:example.org/$evento",
            "entra aqui: https://matrix.to/#/!abc:example.org",
            "https://example.org/#/!abc:example.org",
        ] {
            assert!(
                parse_join_target(input).is_none(),
                "deveria recusar {input:?}"
            );
        }
    }

    fn join_responds(template: ResponseTemplate) -> Mock {
        Mock::given(method("POST"))
            .and(path_regex(r"^/_matrix/client/v3/join/"))
            .respond_with(template)
    }

    fn joined(room_id: &str) -> ResponseTemplate {
        ResponseTemplate::new(200).set_body_json(json!({ "room_id": room_id }))
    }

    async fn join_url(server: &MatrixMockServer) -> url::Url {
        let requests = server.server().received_requests().await.unwrap();
        requests
            .iter()
            .find(|request| request.url.path().contains("/join/"))
            .expect("join enviado")
            .url
            .clone()
    }

    #[tokio::test]
    async fn join_room_sends_via_from_the_link() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "join_via_link").await;
        join_responds(joined("!abc:example.org"))
            .expect(1)
            .mount(server.server())
            .await;

        let room_id = client
            .join_room("https://matrix.to/#/!abc:example.org?via=other.org".to_owned())
            .await
            .unwrap();

        assert_eq!(room_id, "!abc:example.org");
        assert_eq!(join_url(&server).await.query(), Some("via=other.org"));
        assert!(client.find_room("!abc:example.org").is_some());
    }

    #[tokio::test]
    async fn join_room_without_via_uses_the_server_of_the_id() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "join_via_id").await;
        join_responds(joined("!abc:example.org"))
            .mount(server.server())
            .await;

        client
            .join_room("!abc:example.org".to_owned())
            .await
            .unwrap();

        assert_eq!(join_url(&server).await.query(), Some("via=example.org"));
    }

    #[tokio::test]
    async fn join_room_by_alias_resolves_it() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "join_alias").await;
        server
            .mock_room_directory_resolve_alias()
            .ok("!abc:example.org", vec!["example.org".to_owned()])
            .mount()
            .await;
        join_responds(joined("!abc:example.org"))
            .mount(server.server())
            .await;

        let room_id = client
            .join_room("#sala:example.org".to_owned())
            .await
            .unwrap();

        assert_eq!(room_id, "!abc:example.org");
    }

    #[tokio::test]
    async fn join_room_maps_server_errors() {
        let cases = [
            (api_error(404, "M_NOT_FOUND"), JoinRoomErrorKind::NotFound),
            (api_error(403, "M_FORBIDDEN"), JoinRoomErrorKind::Forbidden),
            (ResponseTemplate::new(500), JoinRoomErrorKind::Network),
            (api_error(400, "M_UNKNOWN"), JoinRoomErrorKind::Unknown),
            (api_error(404, "M_UNKNOWN"), JoinRoomErrorKind::NotFound),
        ];
        for (index, (template, kind)) in cases.into_iter().enumerate() {
            let server = MatrixMockServer::new().await;
            let client = created_client(&server, &format!("join_error_{index}")).await;
            join_responds(template).mount(server.server()).await;

            let error = client
                .join_room("!abc:example.org".to_owned())
                .await
                .unwrap_err();

            assert_eq!(error.kind, kind, "caso {index}");
        }
    }

    #[tokio::test]
    async fn join_room_with_unknown_alias_is_not_found() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "join_alias_missing").await;
        server
            .mock_room_directory_resolve_alias()
            .respond_with(api_error(404, "M_NOT_FOUND"))
            .mount()
            .await;

        let error = client
            .join_room("#nada:example.org".to_owned())
            .await
            .unwrap_err();

        assert_eq!(error.kind, JoinRoomErrorKind::NotFound);
    }

    #[tokio::test]
    async fn join_room_with_invalid_link_sends_nothing() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "join_invalid").await;

        let error = client
            .join_room("@ana:example.org".to_owned())
            .await
            .unwrap_err();

        assert_eq!(error.kind, JoinRoomErrorKind::InvalidLink);
        assert!(server
            .server()
            .received_requests()
            .await
            .unwrap()
            .is_empty());
    }

    #[tokio::test]
    async fn join_room_gives_up_after_the_limit() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "join_timeout").await;
        join_responds(joined("!abc:example.org").set_delay(Duration::from_secs(10)))
            .mount(server.server())
            .await;

        let error = client
            .join_room_within("!abc:example.org", Duration::from_millis(200))
            .await
            .unwrap_err();

        assert_eq!(error.kind, JoinRoomErrorKind::Network);
    }

    #[tokio::test]
    async fn room_link_routes_a_room_without_alias_through_its_members() {
        let server = MatrixMockServer::new().await;
        let inner = server.client_builder().build().await;
        let bob = user_id!("@bob:other.org");
        server
            .sync_room(
                &inner,
                JoinedRoomBuilder::new(room_id!("!pub:example.org"))
                    .add_state_event(EventFactory::new().member(bob).sender(bob)),
            )
            .await;
        let client = MatrixClient::new(inner, temp_data_dir("room_link"), None);

        assert_eq!(
            client
                .room_link("!pub:example.org".to_owned())
                .await
                .as_deref(),
            Some("https://matrix.to/#/!pub:example.org?via=other.org"),
        );
        assert_eq!(
            client.room_link("!naoexiste:example.org".to_owned()).await,
            None
        );
    }
}
