use std::{
    mem::ManuallyDrop,
    sync::{Arc, Mutex},
};

use flutter_rust_bridge::frb;
use matrix_sdk::{ruma::OwnedRoomId, AuthSession, Client, Room, SessionChange};
use tokio::{
    runtime::Handle,
    sync::broadcast::{error::RecvError, Receiver},
    task::AbortHandle,
};

use crate::{
    api::rooms::SyncStatus,
    frb_generated::StreamSink,
    recent_threads::RecentThreads,
    room_list::{RoomSync, RoomSyncStopper},
    session_store::{self, SavedAuth, StoredSession},
    threads::ThreadReads,
};

pub enum SessionEvent {
    Revoked,
}

type EventSink = Arc<Mutex<Option<StreamSink<SessionEvent>>>>;

#[frb(opaque)]
pub struct MatrixClient {
    pub(crate) client: ManuallyDrop<Client>,
    pub(crate) rooms: ManuallyDrop<RoomSync>,
    pub(crate) recent_threads: ManuallyDrop<RecentThreads>,
    pub(crate) runtime: Handle,
    pub(crate) thread_reads: ThreadReads,
    pub(crate) vault: Option<Arc<Vault>>,
    events: EventSink,
    pub(crate) session_watcher: AbortHandle,
}

impl Drop for MatrixClient {
    /// O finalizer do Dart roda fora do runtime Tokio, e o store SQLite do SDK precisa dele ao fechar.
    fn drop(&mut self) {
        self.session_watcher.abort();
        let _guard = self.runtime.enter();
        // SAFETY: `recent_threads`, `rooms` e `client` não são mais acessados depois daqui; o próprio `MatrixClient` está sendo destruído.
        unsafe {
            ManuallyDrop::drop(&mut self.recent_threads);
            ManuallyDrop::drop(&mut self.rooms);
            ManuallyDrop::drop(&mut self.client);
        }
    }
}

impl MatrixClient {
    #[frb(sync, getter)]
    pub fn user_id(&self) -> String {
        self.client
            .user_id()
            .map(ToString::to_string)
            .unwrap_or_default()
    }

    #[frb(sync, getter)]
    pub fn device_id(&self) -> String {
        self.client
            .device_id()
            .map(ToString::to_string)
            .unwrap_or_default()
    }

    #[cfg(test)]
    pub(crate) fn inner(&self) -> &Client {
        &self.client
    }

    #[frb(sync, getter)]
    pub fn session_saved(&self) -> bool {
        self.vault.is_some()
    }

    pub fn session_events(&self, sink: StreamSink<SessionEvent>) {
        *self.events.lock().unwrap() = Some(sink);
    }

    pub(crate) fn find_room(&self, room_id: &str) -> Option<Room> {
        OwnedRoomId::try_from(room_id)
            .ok()
            .and_then(|room_id| self.client.get_room(&room_id))
    }

    #[cfg(test)]
    pub(crate) fn room_sync(&self) -> &RoomSync {
        &self.rooms
    }

    pub(crate) fn new(
        client: Client,
        data_dir: String,
        saved_session: Option<StoredSession>,
    ) -> Self {
        let vault = saved_session.map(|stored| Arc::new(Vault::new(data_dir, stored)));
        if let Some(vault) = &vault {
            save_on_refresh(&client, vault.clone());
        }
        let events = EventSink::default();
        // Inscrito aqui, e não dentro da task, para não perder um evento antes de ela rodar.
        let changes = client.subscribe_to_session_changes();
        let thread_reads = ThreadReads::default();
        let rooms = RoomSync::new(client.clone(), Handle::current());
        let recent_threads = RecentThreads::new(client.clone(), Handle::current());
        let loader = recent_threads.loader();
        // Uma busca por sessão, quando o primeiro sync termina e as salas já têm recency_stamp.
        rooms.on_first_running({
            let loader = loader.clone();
            move || loader.load()
        });
        rooms.watch_status(move |status| {
            if matches!(
                status,
                SyncStatus::Offline | SyncStatus::Error | SyncStatus::Unsupported
            ) {
                loader.sync_unavailable();
            }
            true
        });
        let session_watcher = tokio::spawn(watch_session(
            changes,
            vault.clone(),
            events.clone(),
            rooms.stopper(),
        ))
        .abort_handle();
        Self {
            client: ManuallyDrop::new(client),
            rooms: ManuallyDrop::new(rooms),
            recent_threads: ManuallyDrop::new(recent_threads),
            runtime: Handle::current(),
            thread_reads,
            vault,
            events,
            session_watcher,
        }
    }
}

pub(crate) struct Vault {
    data_dir: String,
    homeserver_url: String,
    store_name: String,
    passphrase: String,
    // O delete segura o lock, então nenhum save termina depois dele.
    active: Mutex<bool>,
}

impl Vault {
    fn new(data_dir: String, stored: StoredSession) -> Self {
        Self {
            data_dir,
            homeserver_url: stored.homeserver_url,
            store_name: stored.store_name,
            passphrase: stored.passphrase,
            active: Mutex::new(true),
        }
    }

    fn stored(&self, current: Option<AuthSession>) -> Option<StoredSession> {
        Some(StoredSession {
            homeserver_url: self.homeserver_url.clone(),
            store_name: self.store_name.clone(),
            passphrase: self.passphrase.clone(),
            auth: SavedAuth::from_session(current?)?,
        })
    }

    fn save_tokens(&self, current: Option<AuthSession>) -> Result<(), String> {
        let active = self.active.lock().unwrap();
        match self.stored(current) {
            Some(updated) if *active => session_store::save(&self.data_dir, &updated),
            _ => Ok(()),
        }
    }

    pub(crate) fn forget(&self) -> Result<(), String> {
        let mut active = self.active.lock().unwrap();
        session_store::delete(&self.data_dir)?;
        *active = false;
        Ok(())
    }
}

// O SDK chama o save dentro do próprio refresh, antes de avisar que os tokens mudaram.
fn save_on_refresh(client: &Client, vault: Arc<Vault>) {
    let registered = client.set_session_callbacks(
        // Só é usado com o lock entre processos, que o app não ativa.
        Box::new(|client| client.session_tokens().ok_or_else(|| "sem sessão".into())),
        Box::new(move |client| {
            match vault.save_tokens(client.session()) {
                Ok(()) => log::info!("tokens renovados gravados no cofre"),
                Err(error) => log::warn!("tokens renovados não foram gravados: {error}"),
            }
            Ok(())
        }),
    );
    if let Err(error) = registered {
        log::warn!("callbacks de sessão não registrados: {error}");
    }
}

async fn watch_session(
    mut changes: Receiver<SessionChange>,
    vault: Option<Arc<Vault>>,
    events: EventSink,
    rooms: RoomSyncStopper,
) {
    loop {
        match watch_action(changes.recv().await) {
            WatchAction::Ignore => {}
            WatchAction::Revoke => {
                if let Some(vault) = vault.clone() {
                    if let Err(error) = run_blocking(move || vault.forget()).await {
                        log::warn!("sessão revogada não foi apagada do cofre: {error}");
                    }
                }
                // Com o modo offline, o SDK religaria o sync a cada 401 até o processo acabar.
                rooms.stop().await;
                if let Some(sink) = events.lock().unwrap().as_ref() {
                    sink.add(SessionEvent::Revoked).ok();
                }
            }
            WatchAction::Stop => break,
        }
    }
}

#[derive(Debug, PartialEq)]
enum WatchAction {
    Ignore,
    Revoke,
    Stop,
}

fn watch_action(change: Result<SessionChange, RecvError>) -> WatchAction {
    match change {
        Ok(SessionChange::TokensRefreshed) | Err(RecvError::Lagged(_)) => WatchAction::Ignore,
        Ok(SessionChange::UnknownToken(_)) => WatchAction::Revoke,
        Err(RecvError::Closed) => WatchAction::Stop,
    }
}

pub(crate) async fn run_blocking<T: Send + 'static>(
    task: impl FnOnce() -> T + Send + 'static,
) -> T {
    tokio::task::spawn_blocking(task)
        .await
        .unwrap_or_else(|error| std::panic::resume_unwind(error.into_panic()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    use matrix_sdk::{
        authentication::oauth::{ClientId, OAuthSession, UserSession},
        ruma::api::error::UnknownTokenErrorData,
    };

    use crate::test_support::{session_meta, temp_data_dir, tokens};

    fn vault() -> Vault {
        Vault::new("dir".into(), stored_oauth("velho"))
    }

    fn stored_oauth(refresh: &str) -> StoredSession {
        StoredSession {
            homeserver_url: "https://matrix-client.matrix.org/".into(),
            store_name: "login_1".into(),
            passphrase: "segredo".into(),
            auth: SavedAuth::OAuth {
                client_id: "client".into(),
                user: UserSession {
                    meta: session_meta(),
                    tokens: tokens(refresh),
                },
            },
        }
    }

    #[test]
    fn refreshed_or_lagged_events_are_ignored() {
        assert_eq!(
            watch_action(Ok(SessionChange::TokensRefreshed)),
            WatchAction::Ignore
        );
        assert_eq!(watch_action(Err(RecvError::Lagged(2))), WatchAction::Ignore);
    }

    #[test]
    fn unknown_token_revokes_and_closed_channel_stops() {
        assert_eq!(
            watch_action(Ok(
                SessionChange::UnknownToken(UnknownTokenErrorData::new())
            )),
            WatchAction::Revoke
        );
        assert_eq!(watch_action(Err(RecvError::Closed)), WatchAction::Stop);
    }

    #[test]
    fn vault_keeps_store_and_takes_current_tokens() {
        let current = AuthSession::OAuth(Box::new(OAuthSession {
            client_id: ClientId::new("client".into()),
            user: UserSession {
                meta: session_meta(),
                tokens: tokens("novo"),
            },
        }));

        let updated = vault().stored(Some(current)).unwrap();

        assert_eq!(updated.store_name, "login_1");
        assert_eq!(updated.passphrase, "segredo");
        let SavedAuth::OAuth { user, .. } = updated.auth else {
            panic!("deveria ser OAuth");
        };
        assert_eq!(user.tokens.refresh_token.as_deref(), Some("novo"));
    }

    #[test]
    fn vault_without_current_session_is_none() {
        assert!(vault().stored(None).is_none());
    }

    #[tokio::test]
    async fn revocation_stops_room_sync() {
        use std::sync::atomic::{AtomicUsize, Ordering};

        use matrix_sdk::test_utils::mocks::MatrixMockServer;
        use wiremock::{
            matchers::{method, path_regex},
            Mock, ResponseTemplate,
        };

        let server = MatrixMockServer::new().await;
        let client = server.client_builder().no_server_versions().build().await;
        server
            .mock_versions()
            .with_simplified_sliding_sync()
            .ok()
            .mount()
            .await;
        let syncs = Arc::new(AtomicUsize::new(0));
        let counter = syncs.clone();
        Mock::given(method("POST"))
            .and(path_regex(r"/org.matrix.simplified_msc3575/sync$"))
            .respond_with(move |_: &wiremock::Request| {
                counter.fetch_add(1, Ordering::SeqCst);
                ResponseTemplate::new(401).set_body_json(serde_json::json!({
                    "errcode": "M_UNKNOWN_TOKEN", "error": "revogado"
                }))
            })
            .mount(server.server())
            .await;
        let client = MatrixClient::new(client, temp_data_dir("revocation_sync"), None);

        client.room_sync().watch_rooms(|_| true);
        tokio::time::timeout(Duration::from_secs(5), async {
            while syncs.load(Ordering::SeqCst) == 0 {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .expect("primeiro sync em até 5 s");
        tokio::time::sleep(Duration::from_millis(500)).await;
        let before = syncs.load(Ordering::SeqCst);
        tokio::time::sleep(Duration::from_secs(1)).await;

        let after = syncs.load(Ordering::SeqCst);
        assert_eq!(before, after, "o sync continuou depois da revogação");
        let state = client.room_sync().service().unwrap().state().get();
        assert!(
            matches!(state, matrix_sdk_ui::sync_service::State::Idle),
            "{state:?}"
        );
    }
}
