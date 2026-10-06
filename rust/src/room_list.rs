use std::{
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};

use eyeball_im::Vector;
use futures_util::pin_mut;
use matrix_sdk::{
    latest_events::LatestEventValue,
    ruma::{
        api::FeatureFlag,
        events::{room::message::MessageType, AnySyncMessageLikeEvent, AnySyncTimelineEvent},
        serde::Raw,
        UserId,
    },
    Client, Room, RoomDisplayName, RoomHeroWithProfile, RoomState,
};
use matrix_sdk_ui::{
    room_list_service::{
        filters::{
            new_filter_all, new_filter_deduplicate_versions, new_filter_non_left, new_filter_not,
            new_filter_space,
        },
        RoomListItem, RoomListLoadingState,
    },
    sync_service::{State, SyncService},
};
use tokio::{
    runtime::Handle,
    sync::{watch, OnceCell},
    task::AbortHandle,
    time::Instant,
};

use crate::api::rooms::{LatestMessage, LatestMessageKind, RoomSummary, SyncStatus};
use crate::diff_window::next_batch;

// Um Running mais curto que isto antes de cair no Offline conta como falha persistente, não falta de rede.
const MIN_STABLE_RUNNING: Duration = Duration::from_secs(5);

// Sem paginação: a lista inteira atravessa a ponte.
const PAGE_SIZE: usize = 100_000;

// Com o padrão do SDK (1), mensagens que chegam juntas viram um buraco e ficam fora do "N novas".
const ROOM_LIST_TIMELINE_LIMIT: u32 = 20;

pub(crate) struct RoomSync {
    inner: Arc<Inner>,
    runtime: Handle,
}

#[derive(Clone)]
pub(crate) struct RoomSyncStopper {
    inner: Arc<Inner>,
}

struct Inner {
    client: Client,
    service: OnceCell<Arc<SyncService>>,
    started: AtomicBool,
    stopped: AtomicBool,
    status: watch::Sender<SyncStatus>,
    tasks: Mutex<Vec<AbortHandle>>,
}

impl RoomSync {
    pub(crate) fn new(client: Client, runtime: Handle) -> Self {
        let (status, _) = watch::channel(SyncStatus::Connecting);
        Self {
            inner: Arc::new(Inner {
                client,
                service: OnceCell::new(),
                started: AtomicBool::new(false),
                stopped: AtomicBool::new(false),
                status,
                tasks: Mutex::default(),
            }),
            runtime,
        }
    }

    pub(crate) fn watch_rooms(&self, emit: impl FnMut(Vec<RoomSummary>) -> bool + Send + 'static) {
        let inner = self.inner.clone();
        let task = self.runtime.spawn(async move {
            if let Some(service) = inner.service().await {
                if let Err(error) = run_room_list(&service, emit).await {
                    log::warn!("lista de salas indisponível: {error}");
                    inner.status.send_replace(SyncStatus::Error);
                }
            }
        });
        self.inner.track(task.abort_handle());
    }

    /// Roda `action` uma única vez, quando o primeiro sync termina.
    pub(crate) fn on_first_running(&self, action: impl Fn() + Send + 'static) {
        let done = AtomicBool::new(false);
        self.watch_status(move |status| {
            if status == SyncStatus::Running && !done.swap(true, Ordering::SeqCst) {
                action();
            }
            true
        });
    }

    pub(crate) fn watch_status(&self, mut emit: impl FnMut(SyncStatus) -> bool + Send + 'static) {
        let mut status = self.inner.status.subscribe();
        let task = self.runtime.spawn(async move {
            loop {
                let current = *status.borrow_and_update();
                if !emit(current) || status.changed().await.is_err() {
                    return;
                }
            }
        });
        self.inner.track(task.abort_handle());
    }

    #[cfg(test)]
    pub(crate) fn service(&self) -> Option<Arc<SyncService>> {
        self.inner.service.get().cloned()
    }

    pub(crate) fn stopper(&self) -> RoomSyncStopper {
        RoomSyncStopper {
            inner: self.inner.clone(),
        }
    }

    pub(crate) async fn stop(&self) {
        self.inner.stop().await;
    }
}

impl RoomSyncStopper {
    pub(crate) async fn stop(&self) {
        self.inner.stop().await;
    }
}

impl Drop for RoomSync {
    // O SyncService roda numa task própria do SDK e não para sozinho quando é solto.
    fn drop(&mut self) {
        self.inner.abort_tasks();
        if let Some(service) = self.inner.service.get().cloned() {
            self.runtime.spawn(async move { service.stop().await });
        }
    }
}

impl Inner {
    fn is_stopped(&self) -> bool {
        self.stopped.load(Ordering::SeqCst)
    }

    fn track(&self, task: AbortHandle) {
        let mut tasks = self.tasks.lock().unwrap();
        if self.is_stopped() {
            task.abort();
        } else {
            tasks.push(task);
        }
    }

    fn abort_tasks(&self) {
        self.stopped.store(true, Ordering::SeqCst);
        for task in self.tasks.lock().unwrap().drain(..) {
            task.abort();
        }
    }

    async fn stop(&self) {
        self.abort_tasks();
        if let Some(service) = self.service.get() {
            service.stop().await;
        }
    }

    // Um stop() concorrente pode ter rodado entre a checagem e o start(); conferir de novo depois fecha a janela.
    async fn start(&self, service: &SyncService) {
        if self.is_stopped() {
            return;
        }
        service.start().await;
        if self.is_stopped() {
            service.stop().await;
        }
    }

    async fn service(self: &Arc<Self>) -> Option<Arc<SyncService>> {
        let mut attempt = 0;
        loop {
            if self.is_stopped() {
                return None;
            }
            if supports_sliding_sync(&self.client).await == Some(false) {
                self.status.send_replace(SyncStatus::Unsupported);
                return None;
            }
            match self
                .service
                .get_or_try_init(|| build_service(&self.client))
                .await
            {
                Ok(service) => {
                    let service = service.clone();
                    if !self.started.swap(true, Ordering::SeqCst) {
                        let supervisor = tokio::spawn(supervise(service.clone(), self.clone()));
                        self.track(supervisor.abort_handle());
                        self.start(&service).await;
                    }
                    return Some(service);
                }
                Err(error) => {
                    log::warn!("falha ao iniciar o sync: {error}");
                    self.status.send_replace(SyncStatus::Error);
                    tokio::time::sleep(retry_delay(attempt)).await;
                    attempt += 1;
                }
            }
        }
    }
}

async fn build_service(
    client: &Client,
) -> Result<Arc<SyncService>, matrix_sdk_ui::sync_service::Error> {
    Ok(Arc::new(
        SyncService::builder(client.clone())
            .with_offline_mode()
            .with_room_list_timeline_limit(ROOM_LIST_TIMELINE_LIMIT)
            .build()
            .await?,
    ))
}

// A doc do SyncService exige chamar start() de novo depois de um erro.
async fn supervise(service: Arc<SyncService>, inner: Arc<Inner>) {
    let mut states = service.state();
    let mut attempt = 0;
    let mut previous = State::Idle;
    // Instante em que entrou em Running e se veio do Offline (religado pelo próprio SDK).
    let mut running: Option<(Instant, bool)> = None;
    loop {
        if inner.is_stopped() {
            return;
        }
        let state = states.get();
        let short_running = running.take().and_then(|(since, from_offline)| {
            if since.elapsed() >= MIN_STABLE_RUNNING {
                attempt = 0;
                None
            } else {
                Some(from_offline)
            }
        });
        match &state {
            State::Running => {
                running = Some((Instant::now(), matches!(previous, State::Offline)));
                // Uma falha de envio desliga a fila da sala; com a conexão de volta, o que ficou pendente sai.
                inner.client.send_queue().set_enabled(true).await;
                inner.status.send_replace(SyncStatus::Running);
            }
            // Servidor alcançável mas o sync falhando: sem isto o modo offline religa na hora, em laço.
            State::Offline
                if matches!(previous, State::Offline)
                    || short_running.is_some_and(|from_offline| from_offline || attempt > 0) =>
            {
                inner.status.send_replace(SyncStatus::Error);
                service.stop().await;
                tokio::time::sleep(retry_delay(attempt)).await;
                attempt += 1;
                inner.start(&service).await;
            }
            State::Error(_) | State::Terminated => {
                inner.status.send_replace(SyncStatus::Error);
                tokio::time::sleep(retry_delay(attempt)).await;
                attempt += 1;
                inner.start(&service).await;
            }
            State::Idle | State::Offline => {
                inner.status.send_replace(status_of(&state));
            }
        }
        previous = state;
        if states.next().await.is_none() {
            return;
        }
    }
}

async fn run_room_list(
    service: &SyncService,
    mut emit: impl FnMut(Vec<RoomSummary>) -> bool,
) -> Result<(), matrix_sdk_ui::room_list_service::Error> {
    let room_list = service.room_list_service().all_rooms().await?;
    // Antes do primeiro sync a lista vem vazia; esperar evita mostrar "nenhuma conversa" no primeiro login.
    let mut loading = room_list.loading_state();
    while matches!(loading.get(), RoomListLoadingState::NotLoaded) {
        if loading.next().await.is_none() {
            return Ok(());
        }
    }
    let (stream, controller) = room_list.entries_with_dynamic_adapters(PAGE_SIZE);
    controller.set_filter(Box::new(new_filter_all(vec![
        Box::new(new_filter_non_left()),
        Box::new(new_filter_not(Box::new(new_filter_space()))),
        Box::new(new_filter_deduplicate_versions()),
    ])));
    pin_mut!(stream);
    let mut rooms: Vector<RoomListItem> = Vector::new();
    while next_batch(&mut stream, &mut rooms).await {
        let mut summaries = Vec::with_capacity(rooms.len());
        for item in rooms.iter() {
            summaries.push(summarize(item).await);
        }
        if !emit(summaries) {
            return Ok(());
        }
    }
    Ok(())
}

async fn supports_sliding_sync(client: &Client) -> Option<bool> {
    client
        .supported_versions()
        .await
        .ok()
        .map(|versions| versions.features.contains(&FeatureFlag::Msc4186))
}

fn status_of(state: &State) -> SyncStatus {
    match state {
        State::Idle => SyncStatus::Connecting,
        State::Running => SyncStatus::Running,
        State::Offline => SyncStatus::Offline,
        State::Terminated | State::Error(_) => SyncStatus::Error,
    }
}

fn retry_delay(attempt: u32) -> Duration {
    Duration::from_secs((2u64 << attempt.min(4)).min(30))
}

fn count(value: u64) -> u32 {
    u32::try_from(value).unwrap_or(u32::MAX)
}

pub(crate) async fn room_name(room: &Room) -> String {
    match room.display_name().await {
        Ok(RoomDisplayName::Named(name))
        | Ok(RoomDisplayName::Aliased(name))
        | Ok(RoomDisplayName::Calculated(name))
        | Ok(RoomDisplayName::EmptyWas(name)) => name,
        Ok(RoomDisplayName::Empty) | Err(_) => String::new(),
    }
}

async fn summarize(room: &Room) -> RoomSummary {
    RoomSummary {
        id: room.room_id().to_string(),
        name: room_name(room).await,
        is_direct: room.is_dm(),
        is_invite: room.state() == RoomState::Invited,
        is_public: room.is_public().unwrap_or(false),
        unread_messages: count(room.num_unread_messages()),
        unread_mentions: count(room.num_unread_mentions()),
        member_count: count(room.joined_members_count()),
        heroes: room.heroes().await.into_iter().map(hero_name).collect(),
        latest: latest_message(room).await,
    }
}

fn hero_name(hero: RoomHeroWithProfile) -> String {
    hero.display_name
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| hero.user_id.localpart().to_owned())
}

async fn latest_message(room: &Room) -> Option<LatestMessage> {
    let LatestEventValue::Remote(event) = room.latest_event() else {
        return None;
    };
    let sender = event.sender()?;
    // Sem horário a UI mostraria 01/01; melhor não mostrar prévia.
    let timestamp_ms = i64::from(event.timestamp()?.0);
    let (kind, body) = match event.raw().deserialize() {
        // Numa sala vazia o SDK escolhe o join do próprio usuário; isso não é mensagem.
        Ok(AnySyncTimelineEvent::State(_)) => return None,
        Ok(parsed) => message_kind(&parsed),
        Err(_) => (LatestMessageKind::Other, None),
    };
    Some(LatestMessage {
        sender_name: sender_name(room, &sender).await,
        is_own: sender == room.own_user_id(),
        kind,
        body,
        timestamp_ms,
    })
}

pub(crate) async fn message_from_raw(
    room: &Room,
    raw: &Raw<AnySyncTimelineEvent>,
) -> Option<LatestMessage> {
    let event = raw.deserialize().ok()?;
    let sender = event.sender().to_owned();
    let (kind, body) = message_kind(&event);
    Some(LatestMessage {
        sender_name: sender_name(room, &sender).await,
        is_own: sender == room.own_user_id(),
        kind,
        body,
        timestamp_ms: i64::from(event.origin_server_ts().0),
    })
}

pub(crate) fn latest_timestamp(room: &Room) -> Option<u64> {
    match room.latest_event() {
        LatestEventValue::Remote(event) => event.timestamp().map(|ts| u64::from(ts.0)),
        _ => None,
    }
}

pub(crate) async fn sender_name(room: &Room, sender: &UserId) -> String {
    match room.get_member_no_sync(sender).await {
        Ok(Some(member)) => member.name().to_owned(),
        _ => sender.localpart().to_owned(),
    }
}

pub(crate) fn message_kind(event: &AnySyncTimelineEvent) -> (LatestMessageKind, Option<String>) {
    let AnySyncTimelineEvent::MessageLike(event) = event else {
        return (LatestMessageKind::Other, None);
    };
    match event {
        AnySyncMessageLikeEvent::RoomEncrypted(_) => (LatestMessageKind::Encrypted, None),
        AnySyncMessageLikeEvent::RoomMessage(message) => {
            let Some(original) = message.as_original() else {
                return (LatestMessageKind::Other, None);
            };
            match &original.content.msgtype {
                MessageType::Text(text) => (LatestMessageKind::Text, Some(text.body.clone())),
                MessageType::Notice(notice) => (LatestMessageKind::Text, Some(notice.body.clone())),
                MessageType::Emote(emote) => (LatestMessageKind::Text, Some(emote.body.clone())),
                MessageType::Image(_) => (LatestMessageKind::Image, None),
                MessageType::File(_) | MessageType::Video(_) | MessageType::Audio(_) => {
                    (LatestMessageKind::File, None)
                }
                _ => (LatestMessageKind::Other, None),
            }
        }
        _ => (LatestMessageKind::Other, None),
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use matrix_sdk::{
        ruma::{
            event_id,
            events::room::{join_rules::JoinRule, member::MembershipState},
            room_id, user_id,
        },
        test_utils::mocks::MatrixMockServer,
    };
    use matrix_sdk_test::{event_factory::EventFactory, JoinedRoomBuilder};
    use serde_json::json;
    use tokio::runtime::Handle;
    use wiremock::{
        matchers::{method, path_regex},
        Mock, Request, ResponseTemplate,
    };

    use super::*;
    use crate::test_support::wait_until;

    fn event(kind: &str, content: serde_json::Value) -> AnySyncTimelineEvent {
        serde_json::from_value(json!({
            "type": kind, "event_id": "$e", "sender": "@bob:b.c",
            "origin_server_ts": 1, "content": content
        }))
        .unwrap()
    }

    #[test]
    fn message_kind_by_event_type() {
        let text = event(
            "m.room.message",
            json!({ "msgtype": "m.text", "body": "oi" }),
        );
        assert_eq!(
            message_kind(&text),
            (LatestMessageKind::Text, Some("oi".into()))
        );
        let image = event(
            "m.room.message",
            json!({ "msgtype": "m.image", "body": "x.png", "url": "mxc://b.c/x" }),
        );
        assert_eq!(message_kind(&image).0, LatestMessageKind::Image);
        let file = event(
            "m.room.message",
            json!({ "msgtype": "m.file", "body": "x.pdf", "url": "mxc://b.c/x" }),
        );
        assert_eq!(message_kind(&file).0, LatestMessageKind::File);
        let encrypted = event(
            "m.room.encrypted",
            json!({ "algorithm": "m.megolm.v1.aes-sha2", "ciphertext": "abc", "sender_key": "k", "device_id": "D", "session_id": "s" }),
        );
        assert_eq!(
            message_kind(&encrypted),
            (LatestMessageKind::Encrypted, None)
        );
        let reaction = event(
            "m.reaction",
            json!({ "m.relates_to": { "rel_type": "m.annotation", "event_id": "$x", "key": "👍" } }),
        );
        assert_eq!(message_kind(&reaction), (LatestMessageKind::Other, None));
    }

    #[test]
    fn hero_without_display_name_falls_back_to_localpart() {
        let hero = |display_name: Option<&str>| {
            RoomHeroWithProfile::from(matrix_sdk::RoomHero {
                user_id: user_id!("@bob:b.c").to_owned(),
                display_name: display_name.map(str::to_owned),
                avatar_url: None,
            })
        };
        assert_eq!(hero_name(hero(Some("Bob"))), "Bob");
        assert_eq!(hero_name(hero(Some(""))), "bob");
        assert_eq!(hero_name(hero(None)), "bob");
    }

    #[test]
    fn retry_delay_doubles_up_to_30_seconds() {
        let delays: Vec<u64> = (0..6)
            .map(|attempt| retry_delay(attempt).as_secs())
            .collect();
        assert_eq!(delays, vec![2, 4, 8, 16, 30, 30]);
    }

    #[tokio::test]
    async fn summarize_reads_latest_text_message() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        client.event_cache().subscribe().unwrap();
        let room_id = room_id!("!a:b.c");
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_timeline_event(
                    EventFactory::new()
                        .room(room_id)
                        .text_msg("Oi, tudo bem?")
                        .sender(user_id!("@bob:b.c"))
                        .event_id(event_id!("$1")),
                ),
            )
            .await;
        // O último evento é calculado numa task do SDK.
        let summary = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let summary = summarize(&room).await;
                if summary.latest.is_some() {
                    return summary;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .expect("última mensagem em até 5 s");

        assert_eq!(summary.id, "!a:b.c");
        assert!(summary.name.is_empty());
        let latest = summary.latest.expect("última mensagem");
        assert_eq!(latest.kind, LatestMessageKind::Text);
        assert_eq!(latest.body.as_deref(), Some("Oi, tudo bem?"));
        assert_eq!(latest.sender_name, "bob");
        assert!(!latest.is_own);
    }

    #[tokio::test]
    async fn summarize_has_no_preview_when_the_latest_event_is_the_own_join() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        client.event_cache().subscribe().unwrap();
        let room_id = room_id!("!a:b.c");
        let me = client.user_id().unwrap().to_owned();
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_timeline_event(
                    EventFactory::new()
                        .room(room_id)
                        .member(&me)
                        .membership(MembershipState::Join)
                        .sender(&me)
                        .event_id(event_id!("$j")),
                ),
            )
            .await;
        // Espera o SDK escolher o join como último evento antes de afirmar a ausência de prévia.
        tokio::time::timeout(Duration::from_secs(5), async {
            while latest_timestamp(&room).is_none() {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .expect("join como último evento em até 5 s");

        assert!(summarize(&room).await.latest.is_none());
    }

    #[tokio::test]
    async fn summarize_reads_whether_the_room_is_public() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        client.event_cache().subscribe().unwrap();
        let bob = user_id!("@bob:b.c");
        let public = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id!("!pub:b.c")).add_state_event(
                    EventFactory::new()
                        .room_join_rules(JoinRule::Public)
                        .sender(bob),
                ),
            )
            .await;
        let private = server
            .sync_room(&client, JoinedRoomBuilder::new(room_id!("!priv:b.c")))
            .await;

        assert!(summarize(&public).await.is_public);
        assert!(!summarize(&private).await.is_public);
    }

    // Responde a cada 50 ms, mais rápido que a janela de 100 ms da emissão.
    async fn mock_sliding_sync(server: &MatrixMockServer) {
        Mock::given(method("POST"))
            .and(path_regex(r"/org.matrix.simplified_msc3575/sync$"))
            .respond_with(|request: &Request| {
                let body: serde_json::Value = request.body_json().unwrap();
                let mut response = json!({ "txn_id": body.get("txn_id"), "pos": "1" });
                if body.get("conn_id").and_then(|id| id.as_str()) == Some("room-list") {
                    response["lists"] = json!({ "all_rooms": { "count": 2 } });
                    response["rooms"] = json!({
                        "!a:b.c": {
                            "initial": true,
                            "required_state": [{
                                "type": "m.room.name", "state_key": "", "event_id": "$n1",
                                "sender": "@bob:b.c", "origin_server_ts": 900,
                                "content": { "name": "Sala A" }
                            }],
                            "timeline": [{
                                "type": "m.room.message", "event_id": "$a1", "sender": "@bob:b.c",
                                "origin_server_ts": 1000,
                                "content": { "msgtype": "m.text", "body": "olá" }
                            }]
                        },
                        "!b:b.c": { "initial": true, "timeline": [] }
                    });
                }
                ResponseTemplate::new(200)
                    .set_body_json(response)
                    .set_delay(Duration::from_millis(50))
            })
            .mount(server.server())
            .await;
    }

    #[tokio::test]
    async fn watch_rooms_emits_sorted_summaries_and_stop_idles_the_service() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().no_server_versions().build().await;
        server
            .mock_versions()
            .with_simplified_sliding_sync()
            .ok()
            .mount()
            .await;
        mock_sliding_sync(&server).await;
        let sync = RoomSync::new(client, Handle::current());
        let (rooms_tx, mut rooms_rx) = tokio::sync::mpsc::unbounded_channel();
        sync.watch_rooms(move |rooms| rooms_tx.send(rooms).is_ok());
        let (status_tx, mut status_rx) = tokio::sync::mpsc::unbounded_channel();
        sync.watch_status(move |status| status_tx.send(status).is_ok());

        let mut rooms = Vec::new();
        while rooms.len() < 2 {
            rooms = tokio::time::timeout(Duration::from_secs(5), rooms_rx.recv())
                .await
                .expect("lista em até 5 s")
                .expect("canal aberto");
        }

        assert_eq!(rooms[0].name, "Sala A");
        assert_eq!(rooms[0].unread_messages, 1);
        assert_eq!(
            rooms[0]
                .latest
                .as_ref()
                .and_then(|latest| latest.body.as_deref()),
            Some("olá")
        );
        assert!(rooms[1].name.is_empty());
        let mut statuses = Vec::new();
        while let Ok(status) = status_rx.try_recv() {
            statuses.push(status);
        }
        assert!(statuses.contains(&SyncStatus::Running), "{statuses:?}");

        sync.stop().await;
        let state = sync.inner.service.get().unwrap().state().get();
        assert!(matches!(state, State::Idle), "{state:?}");
    }

    #[tokio::test]
    async fn on_first_running_fires_once_when_the_sync_starts() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().no_server_versions().build().await;
        server
            .mock_versions()
            .with_simplified_sliding_sync()
            .ok()
            .mount()
            .await;
        mock_sliding_sync(&server).await;
        let sync = RoomSync::new(client, Handle::current());
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        sync.on_first_running(move || tx.send(()).unwrap());
        sync.watch_rooms(|_| true);

        tokio::time::timeout(Duration::from_secs(5), rx.recv())
            .await
            .expect("disparo em até 5 s");
        sync.stop().await;
        assert!(rx.try_recv().is_err());
    }

    async fn running_sync(server: &MatrixMockServer) -> RoomSync {
        let client = server.client_builder().no_server_versions().build().await;
        server
            .mock_versions()
            .with_simplified_sliding_sync()
            .ok()
            .mount()
            .await;
        mock_sliding_sync(server).await;
        let sync = RoomSync::new(client, Handle::current());
        let (status_tx, mut status_rx) = tokio::sync::mpsc::unbounded_channel();
        sync.watch_status(move |status| status_tx.send(status).is_ok());
        sync.watch_rooms(|_| true);
        tokio::time::timeout(Duration::from_secs(5), async {
            while status_rx.recv().await != Some(SyncStatus::Running) {}
        })
        .await
        .expect("sync rodando em até 5 s");
        sync
    }

    async fn wait_idle(service: &SyncService) {
        let mut states = service.state();
        tokio::time::timeout(Duration::from_secs(5), async {
            while !matches!(states.get(), State::Idle) {
                states.next().await;
            }
        })
        .await
        .unwrap_or_else(|_| panic!("serviço ainda em {:?}", service.state().get()));
    }

    #[tokio::test]
    async fn room_list_asks_for_the_burst_window_of_each_room() {
        let server = MatrixMockServer::new().await;
        let sync = running_sync(&server).await;
        let room_list_limits = || async {
            let requests = server.server().received_requests().await.unwrap();
            requests
                .iter()
                .filter_map(|request| request.body_json::<serde_json::Value>().ok())
                .filter(|body| body["conn_id"] == "room-list")
                .map(|body| body["lists"]["all_rooms"]["timeline_limit"].clone())
                .collect::<Vec<_>>()
        };

        wait_until(|| async { !room_list_limits().await.is_empty() }).await;

        let limits = room_list_limits().await;
        assert!(
            limits
                .iter()
                .all(|limit| *limit == json!(ROOM_LIST_TIMELINE_LIMIT)),
            "{limits:?}"
        );
        sync.stop().await;
    }

    #[tokio::test]
    async fn drop_stops_the_sync_service() {
        let server = MatrixMockServer::new().await;
        let sync = running_sync(&server).await;
        let service = sync.inner.service.get().unwrap().clone();

        drop(sync);

        wait_idle(&service).await;
    }

    #[tokio::test]
    async fn running_reenables_the_send_queue() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().no_server_versions().build().await;
        server
            .mock_versions()
            .with_simplified_sliding_sync()
            .ok()
            .mount()
            .await;
        mock_sliding_sync(&server).await;
        client.send_queue().set_enabled(false).await;
        let sync = RoomSync::new(client.clone(), Handle::current());
        let (status_tx, mut status_rx) = tokio::sync::mpsc::unbounded_channel();
        sync.watch_status(move |status| status_tx.send(status).is_ok());
        sync.watch_rooms(|_| true);

        tokio::time::timeout(Duration::from_secs(5), async {
            while status_rx.recv().await != Some(SyncStatus::Running) {}
        })
        .await
        .expect("sync rodando em até 5 s");

        assert!(client.send_queue().is_enabled());
    }

    #[tokio::test]
    async fn persistent_sync_error_backs_off_instead_of_looping() {
        use std::sync::atomic::{AtomicUsize, Ordering};

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
            .respond_with(move |_: &Request| {
                counter.fetch_add(1, Ordering::SeqCst);
                ResponseTemplate::new(403)
                    .set_body_json(json!({ "errcode": "M_FORBIDDEN", "error": "proibido" }))
            })
            .mount(server.server())
            .await;
        let sync = RoomSync::new(client, Handle::current());
        let (status_tx, mut status_rx) = tokio::sync::mpsc::unbounded_channel();
        sync.watch_status(move |status| status_tx.send(status).is_ok());
        sync.watch_rooms(|_| true);

        tokio::time::timeout(Duration::from_secs(5), async {
            while status_rx.recv().await != Some(SyncStatus::Error) {}
        })
        .await
        .expect("erro em até 5 s");
        let before = syncs.load(Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(1500)).await;

        let during_backoff = syncs.load(Ordering::SeqCst) - before;
        assert!(during_backoff <= 4, "{during_backoff} syncs em 1,5 s");
    }

    #[tokio::test]
    async fn server_without_sliding_sync_reports_unsupported() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().no_server_versions().build().await;
        server.mock_versions().ok().mount().await;
        let sync = RoomSync::new(client, Handle::current());
        let (rooms_tx, mut rooms_rx) = tokio::sync::mpsc::unbounded_channel();
        sync.watch_rooms(move |rooms| rooms_tx.send(rooms).is_ok());
        let (status_tx, mut status_rx) = tokio::sync::mpsc::unbounded_channel();
        sync.watch_status(move |status| status_tx.send(status).is_ok());

        let mut status = SyncStatus::Connecting;
        while status != SyncStatus::Unsupported {
            status = tokio::time::timeout(Duration::from_secs(5), status_rx.recv())
                .await
                .expect("status em até 5 s")
                .expect("canal aberto");
        }

        assert!(rooms_rx.recv().await.is_none(), "nenhuma lista emitida");
        assert!(sync.inner.service.get().is_none());
    }
}
