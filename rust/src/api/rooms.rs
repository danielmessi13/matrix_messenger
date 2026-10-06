use std::time::Duration;

use matrix_sdk::{
    config::RequestConfig,
    ruma::{
        api::{
            client::{
                profile::get_profile,
                room::create_room::v3::{Request as CreateRoomRequest, RoomPreset},
            },
            error::ErrorKind,
        },
        events::{room::encryption::RoomEncryptionEventContent, InitialStateEvent},
        matrix_uri::MatrixId,
        MatrixToUri, MatrixUri, OwnedRoomOrAliasId, OwnedServerName, RoomOrAliasId, UserId,
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

#[derive(Debug, Clone, PartialEq)]
pub struct NewRoom {
    pub name: String,
    pub topic: Option<String>,
    pub is_public: bool,
    pub invites: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CreatedRoom {
    pub room_id: String,
    pub failed_invites: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum CreateRoomErrorKind {
    Network,
    Unknown,
}

#[derive(Debug)]
pub struct CreateRoomError {
    pub kind: CreateRoomErrorKind,
    pub message: String,
}

impl From<matrix_sdk::Error> for CreateRoomError {
    fn from(error: matrix_sdk::Error) -> Self {
        // Resposta com código da API (ex.: 403) chegou ao servidor; não é falta de conexão.
        let kind = match &error {
            matrix_sdk::Error::Http(_) if error.client_api_error_kind().is_none() => {
                CreateRoomErrorKind::Network
            }
            _ => CreateRoomErrorKind::Unknown,
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

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum UserCheckStatus {
    Found,
    NotFound,
    Unknown,
}

#[derive(Debug, Clone, PartialEq)]
pub struct UserCheck {
    pub status: UserCheckStatus,
    pub display_name: Option<String>,
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

    pub async fn create_room(&self, room: NewRoom) -> Result<CreatedRoom, CreateRoomError> {
        self.create_room_within(room, ROOM_REQUEST_TIMEOUT).await
    }

    async fn create_room_within(
        &self,
        room: NewRoom,
        limit: Duration,
    ) -> Result<CreatedRoom, CreateRoomError> {
        let mut request = CreateRoomRequest::new();
        request.name = Some(room.name);
        request.topic = room.topic;
        if room.is_public {
            request.preset = Some(RoomPreset::PublicChat);
        } else {
            request.preset = Some(RoomPreset::PrivateChat);
            request.initial_state = vec![InitialStateEvent::with_empty_state_key(
                RoomEncryptionEventContent::with_recommended_defaults(),
            )
            .to_raw_any()];
        }
        let created = tokio::time::timeout(limit, self.client.create_room(request))
            .await
            .map_err(|_| CreateRoomError {
                kind: CreateRoomErrorKind::Network,
                message: format!("sem resposta do servidor em {limit:?}"),
            })??;

        // Convidar depois da criação: um ID ruim não derruba a sala.
        let mut failed_invites = Vec::new();
        for invite in room.invites {
            let invited = match UserId::parse(invite.as_str()) {
                Ok(user_id) => created.invite_user_by_id(&user_id).await.is_ok(),
                Err(_) => false,
            };
            if !invited {
                failed_invites.push(invite);
            }
        }
        Ok(CreatedRoom {
            room_id: created.room_id().to_string(),
            failed_invites,
        })
    }

    pub async fn check_user(&self, user_id: String) -> UserCheck {
        let not_found = UserCheck {
            status: UserCheckStatus::NotFound,
            display_name: None,
        };
        let Ok(user_id) = UserId::parse(user_id.as_str()) else {
            return not_found;
        };
        // Sem retry: o chip ficaria em "verificando" enquanto o SDK insiste em 5xx/429.
        let request = get_profile::v3::Request::new(user_id);
        let config = RequestConfig::new().disable_retry().force_auth();
        match self.client.send(request).with_request_config(config).await {
            Ok(profile) => UserCheck {
                status: UserCheckStatus::Found,
                display_name: profile
                    .get("displayname")
                    .and_then(|name| name.as_str())
                    .map(str::to_owned),
            },
            Err(error) if error.client_api_error_kind() == Some(&ErrorKind::NotFound) => not_found,
            // 403 (servidor restringe perfis) e rede: não dá para saber; o convite decide.
            Err(_) => UserCheck {
                status: UserCheckStatus::Unknown,
                display_name: None,
            },
        }
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
    use std::time::{Duration, Instant};

    use matrix_sdk::{
        ruma::{room_id, user_id},
        test_utils::{client::MockClientBuilder, mocks::MatrixMockServer},
        RoomState,
    };
    use matrix_sdk_test::{event_factory::EventFactory, InvitedRoomBuilder, JoinedRoomBuilder};
    use serde_json::{json, Value};
    use wiremock::{
        matchers::{method, path_regex},
        Mock, ResponseTemplate,
    };

    use super::*;
    use crate::test_support::{env_var, offline_client, temp_data_dir};

    async fn client_with_invite(server: &MatrixMockServer, name: &str) -> (MatrixClient, Room) {
        let client = server.client_builder().build().await;
        let room = server
            .sync_room(
                &client,
                InvitedRoomBuilder::new(room_id!("!convite:example.org")),
            )
            .await;
        (MatrixClient::new(client, temp_data_dir(name), None), room)
    }

    #[tokio::test]
    async fn accept_invite_joins_the_room() {
        let server = MatrixMockServer::new().await;
        let (client, room) = client_with_invite(&server, "accept_invite").await;
        server
            .mock_room_join(room.room_id())
            .ok()
            .expect(1)
            .mount()
            .await;

        client
            .accept_invite(room.room_id().to_string())
            .await
            .unwrap();

        assert_eq!(room.state(), RoomState::Joined);
    }

    #[tokio::test]
    async fn decline_invite_leaves_and_forgets_the_room() {
        let server = MatrixMockServer::new().await;
        let (client, room) = client_with_invite(&server, "decline_invite").await;
        server
            .mock_room_leave()
            .ok(room.room_id())
            .expect(1)
            .mount()
            .await;
        server.mock_room_forget().ok().expect(1).mount().await;

        client
            .decline_invite(room.room_id().to_string())
            .await
            .unwrap();

        assert!(client.find_room(room.room_id().as_str()).is_none());
    }

    #[tokio::test]
    async fn failed_accept_invite_is_network_error() {
        let server = MatrixMockServer::new().await;
        let (client, room) = client_with_invite(&server, "accept_invite_fails").await;
        server
            .mock_room_join(room.room_id())
            .error500()
            .mount()
            .await;

        let error = client
            .accept_invite(room.room_id().to_string())
            .await
            .unwrap_err();

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
            true,
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

    fn new_room(is_public: bool, invites: &[&str]) -> NewRoom {
        NewRoom {
            name: "Plantão".to_owned(),
            topic: Some("Coordenação".to_owned()),
            is_public,
            invites: invites.iter().map(|id| (*id).to_owned()).collect(),
        }
    }

    async fn created_client(server: &MatrixMockServer, name: &str) -> MatrixClient {
        MatrixClient::new(
            server.client_builder().build().await,
            temp_data_dir(name),
            None,
        )
    }

    async fn create_room_body(server: &MatrixMockServer) -> Value {
        let requests = server.server().received_requests().await.unwrap();
        let request = requests
            .iter()
            .find(|request| request.url.path().ends_with("/createRoom"))
            .expect("createRoom enviado");
        serde_json::from_slice(&request.body).unwrap()
    }

    fn api_error(status: u16, errcode: &str) -> ResponseTemplate {
        ResponseTemplate::new(status).set_body_json(json!({ "errcode": errcode, "error": "x" }))
    }

    #[tokio::test]
    async fn create_private_room_is_encrypted_without_invites_in_request() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "create_private").await;
        server.mock_create_room().ok().expect(1).mount().await;

        let created = client.create_room(new_room(false, &[])).await.unwrap();

        assert_eq!(created.room_id, "!room:example.org");
        assert!(created.failed_invites.is_empty());
        let body = create_room_body(&server).await;
        assert_eq!(body["preset"], "private_chat");
        assert_eq!(body["name"], "Plantão");
        assert_eq!(body["topic"], "Coordenação");
        assert_eq!(body["initial_state"][0]["type"], "m.room.encryption");
        assert!(body.get("invite").is_none());
        assert!(body.get("visibility").is_none());
    }

    #[tokio::test]
    async fn create_public_room_is_not_encrypted() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "create_public").await;
        server.mock_create_room().ok().mount().await;

        client
            .create_room(NewRoom {
                topic: None,
                ..new_room(true, &[])
            })
            .await
            .unwrap();

        let body = create_room_body(&server).await;
        assert_eq!(body["preset"], "public_chat");
        assert!(body.get("initial_state").is_none());
        assert!(body.get("topic").is_none());
    }

    #[tokio::test]
    async fn failed_invites_do_not_undo_the_room() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "create_invites").await;
        server.mock_create_room().ok().mount().await;
        server
            .mock_invite_user_by_id()
            .ok()
            .up_to_n_times(1)
            .expect(1)
            .mount()
            .await;
        server
            .mock_invite_user_by_id()
            .respond_with(api_error(404, "M_NOT_FOUND"))
            .mount()
            .await;

        let created = client
            .create_room(new_room(
                false,
                &["@ana:example.org", "@joao:example.org", "isto não é id"],
            ))
            .await
            .unwrap();

        assert_eq!(created.room_id, "!room:example.org");
        assert_eq!(
            created.failed_invites,
            vec!["@joao:example.org", "isto não é id"]
        );
    }

    #[tokio::test]
    async fn create_room_with_server_error_500_is_network_error() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "create_500").await;
        server.mock_create_room().error500().mount().await;

        let error = client.create_room(new_room(false, &[])).await.unwrap_err();

        assert_eq!(error.kind, CreateRoomErrorKind::Network);
    }

    #[tokio::test]
    async fn create_room_with_unreachable_server_is_network_error() {
        let client = MatrixClient::new(
            MockClientBuilder::new(Some("http://127.0.0.1:9"))
                .build()
                .await,
            temp_data_dir("create_unreachable"),
            None,
        );

        let error = client.create_room(new_room(false, &[])).await.unwrap_err();

        assert_eq!(error.kind, CreateRoomErrorKind::Network);
    }

    #[tokio::test]
    async fn create_room_gives_up_after_the_limit() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "create_timeout").await;
        server
            .mock_create_room()
            .respond_with(
                ResponseTemplate::new(200)
                    .set_body_json(json!({ "room_id": "!room:example.org" }))
                    .set_delay(Duration::from_secs(10)),
            )
            .mount()
            .await;

        let started = Instant::now();
        let error = client
            .create_room_within(new_room(false, &[]), Duration::from_millis(200))
            .await
            .unwrap_err();

        assert_eq!(error.kind, CreateRoomErrorKind::Network);
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[tokio::test]
    async fn create_room_refused_by_server_is_unknown_error() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "create_forbidden").await;
        server
            .mock_create_room()
            .respond_with(api_error(403, "M_FORBIDDEN"))
            .mount()
            .await;

        let error = client.create_room(new_room(false, &[])).await.unwrap_err();

        assert_eq!(error.kind, CreateRoomErrorKind::Unknown);
    }

    #[tokio::test]
    async fn check_user_reads_the_profile() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "check_user").await;
        server
            .mock_get_profile(user_id!("@ana:example.org"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "displayname": "Ana" })))
            .mount()
            .await;
        server
            .mock_get_profile(user_id!("@semnome:example.org"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({})))
            .mount()
            .await;
        server
            .mock_get_profile(user_id!("@joao:example.org"))
            .respond_with(api_error(404, "M_NOT_FOUND"))
            .mount()
            .await;
        server
            .mock_get_profile(user_id!("@rui:example.org"))
            .respond_with(api_error(403, "M_FORBIDDEN"))
            .mount()
            .await;

        let check = |id: &str| client.check_user(id.to_owned());
        assert_eq!(
            check("@ana:example.org").await,
            UserCheck {
                status: UserCheckStatus::Found,
                display_name: Some("Ana".to_owned())
            },
        );
        assert_eq!(
            check("@semnome:example.org").await,
            UserCheck {
                status: UserCheckStatus::Found,
                display_name: None
            },
        );
        assert_eq!(
            check("@joao:example.org").await.status,
            UserCheckStatus::NotFound
        );
        assert_eq!(
            check("@rui:example.org").await.status,
            UserCheckStatus::Unknown
        );
        assert_eq!(check("joao").await.status, UserCheckStatus::NotFound);
    }

    #[tokio::test]
    async fn check_user_without_connection_is_unknown() {
        let server = MatrixMockServer::new().await;
        let client = created_client(&server, "check_user_network").await;
        server
            .mock_get_profile(user_id!("@ana:example.org"))
            .respond_with(ResponseTemplate::new(500))
            .mount()
            .await;

        assert_eq!(
            client
                .check_user("@ana:example.org".to_owned())
                .await
                .status,
            UserCheckStatus::Unknown,
        );
    }

    #[tokio::test]
    async fn check_user_does_not_retry_server_errors() {
        let server = MatrixMockServer::new().await;
        // Retry do SDK ligado, como no app.
        let sdk_client = server
            .client_builder()
            .on_builder(|builder| builder.request_config(RequestConfig::new()))
            .build()
            .await;
        let client = MatrixClient::new(sdk_client, temp_data_dir("check_user_no_retry"), None);
        server
            .mock_get_profile(user_id!("@ana:example.org"))
            .respond_with(ResponseTemplate::new(500))
            .expect(1)
            .mount()
            .await;

        let started = Instant::now();
        let check = client.check_user("@ana:example.org".to_owned()).await;

        assert_eq!(check.status, UserCheckStatus::Unknown);
        assert!(started.elapsed() < Duration::from_secs(2));
        server.server().verify().await;
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
