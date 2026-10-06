use std::{
    cmp::Reverse,
    collections::{HashMap, HashSet},
    future::Future,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex, Weak,
    },
};

use futures_util::{future::join_all, pin_mut, StreamExt};
use matrix_sdk::{
    deserialized_responses::TimelineEvent,
    room::ListThreadsOptions,
    ruma::{
        api::client::threads::get_threads::v1::IncludeThreads,
        events::{room::encrypted::OriginalSyncRoomEncryptedEvent, AnySyncTimelineEvent},
        serde::Raw,
        OwnedEventId, OwnedRoomId, UInt,
    },
    serde_helpers::extract_thread_root,
    sync::RoomUpdates,
    Client, Room, RoomState,
};
use serde::Deserialize;
use tokio::{
    runtime::Handle,
    sync::{broadcast, watch},
    task::AbortHandle,
};

use crate::api::threads::{RecentThread, RecentThreadsSnapshot, RecentThreadsStatus};
use crate::room_list::{latest_timestamp, message_from_raw};

pub(crate) const MAX_THREADS: usize = 10;

pub(crate) const INITIAL_ROOMS: usize = 4;

pub(crate) struct Read {
    pub(crate) root: OwnedEventId,
    pub(crate) latest_reply_id: Option<OwnedEventId>,
    pub(crate) thread: RecentThread,
    pub(crate) missing_sessions: Vec<String>,
}

#[derive(Deserialize)]
struct Unsigned {
    #[serde(rename = "m.relations")]
    relations: Option<Relations>,
}

#[derive(Deserialize)]
struct Relations {
    #[serde(rename = "m.thread")]
    thread: Option<BundledThread>,
}

#[derive(Deserialize)]
struct BundledThread {
    latest_event: Raw<AnySyncTimelineEvent>,
    count: u32,
    #[serde(default)]
    current_user_participated: bool,
}

pub(crate) fn upsert(threads: &mut Vec<RecentThread>, thread: RecentThread) {
    remove(threads, &thread.room_id, &thread.root_event_id);
    threads.push(thread);
    threads.sort_by_key(|thread| Reverse(thread.activity_ms));
    threads.truncate(MAX_THREADS);
}

pub(crate) fn remove(threads: &mut Vec<RecentThread>, room_id: &str, root: &str) {
    threads.retain(|thread| thread.room_id != room_id || thread.root_event_id != root);
}

// Sliding sync preenche o recency_stamp; sem ele, vale o horário do último evento.
pub(crate) fn most_recent<T>(
    mut items: Vec<(T, Option<u64>, Option<u64>)>,
    count: usize,
) -> Vec<T> {
    items.sort_by_key(|(_, stamp, latest)| Reverse((*stamp, *latest)));
    items
        .into_iter()
        .take(count)
        .map(|(item, _, _)| item)
        .collect()
}

pub(crate) fn encrypted_session(raw: &Raw<AnySyncTimelineEvent>) -> Option<String> {
    if raw.get_field::<String>("type").ok()??.as_str() != "m.room.encrypted" {
        return None;
    }
    let content = raw.get_field::<serde_json::Value>("content").ok()??;
    content.get("session_id")?.as_str().map(str::to_owned)
}

// O crypto já decifra o latest_event junto com a raiz; isto cobre raiz em texto claro numa sala que virou cifrada.
async fn decrypt_if_needed(
    room: &Room,
    raw: Raw<AnySyncTimelineEvent>,
) -> Raw<AnySyncTimelineEvent> {
    if encrypted_session(&raw).is_none() {
        return raw;
    }
    match room
        .decrypt_event(
            raw.cast_ref_unchecked::<OriginalSyncRoomEncryptedEvent>(),
            None,
        )
        .await
    {
        Ok(event) => event.into_raw(),
        Err(_) => raw,
    }
}

fn is_redacted(event: &AnySyncTimelineEvent) -> bool {
    matches!(event, AnySyncTimelineEvent::MessageLike(message) if message.original_content().is_none())
}

pub(crate) async fn read_thread(room: &Room, event: &TimelineEvent) -> Option<Read> {
    let root = event.event_id()?;
    let bundled = event
        .raw()
        .get_field::<Unsigned>("unsigned")
        .ok()??
        .relations?
        .thread?;
    if !bundled.current_user_participated || is_redacted(&event.raw().deserialize().ok()?) {
        return None;
    }
    let latest_raw = decrypt_if_needed(room, bundled.latest_event).await;
    let root_message = message_from_raw(room, event.raw()).await?;
    let latest_reply = message_from_raw(room, &latest_raw).await;
    let missing_sessions = [
        encrypted_session(event.raw()),
        encrypted_session(&latest_raw),
    ]
    .into_iter()
    .flatten()
    .collect();
    let activity_ms = latest_reply
        .as_ref()
        .map_or(root_message.timestamp_ms, |reply| reply.timestamp_ms);
    Some(Read {
        thread: RecentThread {
            room_id: room.room_id().to_string(),
            root_event_id: root.to_string(),
            root: root_message,
            latest_reply,
            reply_count: bundled.count,
            activity_ms,
        },
        root: root.to_owned(),
        latest_reply_id: latest_raw.get_field("event_id").ok().flatten(),
        missing_sessions,
    })
}

type Key = (OwnedRoomId, OwnedEventId);

pub(crate) struct RecentThreads {
    inner: Arc<Inner>,
}

// Weak: quem pede a busca não segura o Client vivo depois do logout.
#[derive(Clone)]
pub(crate) struct RecentThreadsLoader(Weak<Inner>);

struct Inner {
    client: Client,
    runtime: Handle,
    snapshot: watch::Sender<RecentThreadsSnapshot>,
    // true = chegou outro evento durante a recarga; recarrega mais uma vez no fim.
    refreshing: Mutex<HashMap<Key, bool>>,
    waiting_keys: Mutex<HashMap<String, HashSet<Key>>>,
    // O backup responde Ok(true) mesmo com uma chave que não decifra; pedir de novo entraria em laço.
    requested_keys: Mutex<HashSet<String>>,
    // Para recarregar a thread quando a última resposta é apagada ou editada.
    latest_replies: Mutex<HashMap<Key, OwnedEventId>>,
    load_started: AtomicBool,
    // None depois do Drop: task nova não sobe e não segura o Client.
    tasks: Mutex<Option<Vec<AbortHandle>>>,
}

impl RecentThreads {
    pub(crate) fn new(client: Client, runtime: Handle) -> Self {
        let (snapshot, _) = watch::channel(RecentThreadsSnapshot {
            status: RecentThreadsStatus::Loading,
            threads: Vec::new(),
        });
        // Inscrito aqui, e não dentro da task, para não perder um sync antes de ela rodar.
        let updates = client.subscribe_to_all_room_updates();
        let inner = Arc::new(Inner {
            client,
            runtime: runtime.clone(),
            snapshot,
            refreshing: Mutex::default(),
            waiting_keys: Mutex::default(),
            requested_keys: Mutex::default(),
            latest_replies: Mutex::default(),
            load_started: AtomicBool::new(false),
            tasks: Mutex::new(Some(Vec::new())),
        });
        inner.spawn(listen_updates(Arc::downgrade(&inner), updates));
        inner.spawn(listen_room_keys(Arc::downgrade(&inner)));
        Self { inner }
    }

    pub(crate) fn loader(&self) -> RecentThreadsLoader {
        RecentThreadsLoader(Arc::downgrade(&self.inner))
    }

    pub(crate) fn watch(
        &self,
        mut emit: impl FnMut(RecentThreadsSnapshot) -> bool + Send + 'static,
    ) {
        let mut snapshot = self.inner.snapshot.subscribe();
        self.inner.spawn(async move {
            loop {
                let current = snapshot.borrow_and_update().clone();
                if !emit(current) || snapshot.changed().await.is_err() {
                    return;
                }
            }
        });
    }
}

impl Drop for RecentThreads {
    fn drop(&mut self) {
        let tasks = self.inner.tasks.lock().unwrap().take();
        for task in tasks.into_iter().flatten() {
            task.abort();
        }
    }
}

impl RecentThreadsLoader {
    pub(crate) fn load(&self) {
        let Some(inner) = self.0.upgrade() else {
            return;
        };
        inner.spawn(inner.clone().load());
    }

    // Sem sync não há busca inicial; sem isto o painel ficaria carregando para sempre.
    pub(crate) fn sync_unavailable(&self) {
        let Some(inner) = self.0.upgrade() else {
            return;
        };
        if inner.load_started.load(Ordering::SeqCst) {
            return;
        }
        inner.snapshot.send_if_modified(|snapshot| {
            let loading = snapshot.status == RecentThreadsStatus::Loading;
            if loading {
                snapshot.status = RecentThreadsStatus::Failed;
            }
            loading
        });
    }
}

impl Inner {
    fn spawn(&self, task: impl Future<Output = ()> + Send + 'static) {
        let mut tasks = self.tasks.lock().unwrap();
        let Some(tasks) = tasks.as_mut() else {
            return;
        };
        tasks.retain(|task| !task.is_finished());
        tasks.push(self.runtime.spawn(task).abort_handle());
    }

    async fn load(self: Arc<Self>) {
        self.load_started.store(true, Ordering::SeqCst);
        self.snapshot
            .send_modify(|snapshot| snapshot.status = RecentThreadsStatus::Loading);
        let candidates = self
            .client
            .joined_rooms()
            .into_iter()
            .map(|room| {
                let stamp = room.recency_stamp().map(u64::from);
                let latest = latest_timestamp(&room);
                (room, stamp, latest)
            })
            .collect();
        let rooms = most_recent(candidates, INITIAL_ROOMS);
        let results = join_all(rooms.iter().map(fetch_room)).await;
        let failed = results.iter().filter(|result| result.is_err()).count();
        let status = if !rooms.is_empty() && failed == rooms.len() {
            RecentThreadsStatus::Failed
        } else {
            RecentThreadsStatus::Ready
        };
        let mut reads = Vec::new();
        for (room, result) in rooms.into_iter().zip(results) {
            match result {
                Ok(found) => reads.extend(found.into_iter().map(|read| (room.clone(), read))),
                Err(error) => log::warn!("threads de {} indisponíveis: {error}", room.room_id()),
            }
        }
        for (room, read) in &reads {
            self.apply(room, read);
        }
        self.snapshot
            .send_modify(|snapshot| snapshot.status = status);
    }

    fn apply(self: &Arc<Self>, room: &Room, read: &Read) {
        let key = (room.room_id().to_owned(), read.root.clone());
        {
            let mut latest = self.latest_replies.lock().unwrap();
            match &read.latest_reply_id {
                Some(id) => latest.insert(key, id.clone()),
                None => latest.remove(&key),
            };
        }
        self.snapshot
            .send_modify(|snapshot| upsert(&mut snapshot.threads, read.thread.clone()));
        self.wait_for_keys(room, read);
    }

    fn forget(&self, room_id: &OwnedRoomId, root: &OwnedEventId) {
        self.latest_replies
            .lock()
            .unwrap()
            .remove(&(room_id.clone(), root.clone()));
        self.snapshot
            .send_modify(|snapshot| remove(&mut snapshot.threads, room_id.as_str(), root.as_str()));
    }

    fn forget_room(&self, room_id: &OwnedRoomId) {
        self.latest_replies
            .lock()
            .unwrap()
            .retain(|(room, _), _| room != room_id);
        self.snapshot.send_if_modified(|snapshot| {
            let before = snapshot.threads.len();
            snapshot
                .threads
                .retain(|thread| thread.room_id != room_id.as_str());
            snapshot.threads.len() != before
        });
    }

    // Raízes listadas desta sala que o evento apaga ou edita, direto ou pela última resposta.
    fn listed_roots_touched_by(
        &self,
        room_id: &OwnedRoomId,
        target: &OwnedEventId,
    ) -> Vec<OwnedEventId> {
        let latest = self.latest_replies.lock().unwrap();
        let snapshot = self.snapshot.borrow();
        snapshot
            .threads
            .iter()
            .filter(|thread| thread.room_id == room_id.as_str())
            .filter_map(|thread| OwnedEventId::try_from(thread.root_event_id.as_str()).ok())
            .filter(|root| {
                root == target
                    || latest.get(&(room_id.clone(), root.clone())) == Some(target)
            })
            .collect()
    }

    fn refresh(self: &Arc<Self>, room_id: OwnedRoomId, root: OwnedEventId) {
        let key = (room_id, root);
        {
            let mut refreshing = self.refreshing.lock().unwrap();
            if let Some(again) = refreshing.get_mut(&key) {
                *again = true;
                return;
            }
            refreshing.insert(key.clone(), false);
        }
        let inner = self.clone();
        self.spawn(async move {
            loop {
                inner.refresh_once(&key).await;
                let again = {
                    let mut refreshing = inner.refreshing.lock().unwrap();
                    if refreshing.get(&key) == Some(&true) {
                        refreshing.insert(key.clone(), false);
                        true
                    } else {
                        refreshing.remove(&key);
                        false
                    }
                };
                if !again {
                    return;
                }
            }
        });
    }

    async fn refresh_once(self: &Arc<Self>, (room_id, root): &Key) {
        let Some(room) = self
            .client
            .get_room(room_id)
            .filter(|room| room.state() == RoomState::Joined)
        else {
            self.forget(room_id, root);
            return;
        };
        let event = match room.event(root, None).await {
            Ok(event) => event,
            Err(error) => {
                log::warn!("thread {root} indisponível: {error}");
                return;
            }
        };
        match read_thread(&room, &event).await {
            Some(read) => self.apply(&room, &read),
            None => self.forget(room_id, root),
        }
    }

    // A chave só vem do backup depois de uma falha, e a falha no latest_event não dispara o download sozinha.
    fn wait_for_keys(self: &Arc<Self>, room: &Room, read: &Read) {
        for session in self.sessions_to_download(room, read) {
            let inner = self.clone();
            let room_id = room.room_id().to_owned();
            self.spawn(async move {
                match inner
                    .client
                    .encryption()
                    .backups()
                    .download_room_key(&room_id, &session)
                    .await
                {
                    Ok(true) => inner.keys_arrived([session.as_str()]),
                    Ok(false) => {}
                    Err(error) => {
                        log::warn!("chave da thread fora do backup: {error}");
                        // Falha transitória: a próxima recarga pode pedir de novo.
                        inner.requested_keys.lock().unwrap().remove(&session);
                    }
                }
            });
        }
    }

    fn sessions_to_download(&self, room: &Room, read: &Read) -> Vec<String> {
        let key = (room.room_id().to_owned(), read.root.clone());
        let mut waiting = self.waiting_keys.lock().unwrap();
        let mut requested = self.requested_keys.lock().unwrap();
        let mut download = Vec::new();
        for session in &read.missing_sessions {
            waiting
                .entry(session.clone())
                .or_default()
                .insert(key.clone());
            if requested.insert(session.clone()) {
                download.push(session.clone());
            }
        }
        download
    }

    fn keys_arrived<'a>(self: &Arc<Self>, sessions: impl IntoIterator<Item = &'a str>) {
        let keys: Vec<Key> = {
            let mut waiting = self.waiting_keys.lock().unwrap();
            sessions
                .into_iter()
                .filter_map(|session| waiting.remove(session))
                .flatten()
                .collect()
        };
        for (room_id, root) in keys {
            self.refresh(room_id, root);
        }
    }
}

async fn fetch_room(room: &Room) -> matrix_sdk::Result<Vec<Read>> {
    let options = ListThreadsOptions {
        include_threads: IncludeThreads::Participated,
        // Uma sala sozinha pode ter as 10 mais recentes.
        limit: Some(UInt::from(MAX_THREADS as u32)),
        ..Default::default()
    };
    let roots = room.list_threads(options).await?;
    let mut reads = Vec::new();
    for root in &roots.chunk {
        if let Some(read) = read_thread(room, root).await {
            reads.push(read);
        }
    }
    Ok(reads)
}

#[derive(Deserialize)]
struct Redaction {
    #[serde(rename = "type")]
    kind: String,
    redacts: Option<OwnedEventId>,
    content: Option<RedactionContent>,
}

#[derive(Deserialize)]
struct RedactionContent {
    redacts: Option<OwnedEventId>,
}

#[derive(Deserialize)]
struct Edit {
    content: EditContent,
}

#[derive(Deserialize)]
struct EditContent {
    #[serde(rename = "m.relates_to")]
    relates_to: Option<RelatesTo>,
}

#[derive(Deserialize)]
struct RelatesTo {
    rel_type: Option<String>,
    event_id: Option<OwnedEventId>,
}

fn edited_target(raw: &Raw<AnySyncTimelineEvent>) -> Option<OwnedEventId> {
    let relation = raw
        .deserialize_as_unchecked::<Edit>()
        .ok()?
        .content
        .relates_to?;
    if relation.rel_type.as_deref() != Some("m.replace") {
        return None;
    }
    relation.event_id
}

// Salas antigas trazem `redacts` no topo do evento; as novas, no content.
fn redacted_target(raw: &Raw<AnySyncTimelineEvent>) -> Option<OwnedEventId> {
    let redaction: Redaction = raw.deserialize_as_unchecked().ok()?;
    if redaction.kind != "m.room.redaction" {
        return None;
    }
    redaction
        .redacts
        .or_else(|| redaction.content.and_then(|content| content.redacts))
}

async fn listen_updates(inner: Weak<Inner>, mut updates: broadcast::Receiver<RoomUpdates>) {
    loop {
        let rooms = match updates.recv().await {
            Ok(rooms) => rooms,
            Err(broadcast::error::RecvError::Lagged(_)) => {
                // Lotes perdidos: só buscar de novo recupera as respostas que vinham neles.
                if let Some(inner) = inner.upgrade() {
                    inner.spawn(inner.clone().load());
                }
                continue;
            }
            Err(broadcast::error::RecvError::Closed) => return,
        };
        let Some(inner) = inner.upgrade() else {
            return;
        };
        for room_id in rooms.left.keys() {
            inner.forget_room(room_id);
        }
        for (room_id, update) in rooms.joined {
            let mut roots: HashSet<OwnedEventId> = update
                .timeline
                .events
                .iter()
                .filter_map(|event| extract_thread_root(event.raw()))
                .collect();
            // Redação e edição não trazem a relação de thread; só interessam se tocam uma thread listada.
            for target in update.timeline.events.iter().filter_map(|event| {
                redacted_target(event.raw()).or_else(|| edited_target(event.raw()))
            }) {
                roots.extend(inner.listed_roots_touched_by(&room_id, &target));
            }
            for root in roots {
                inner.refresh(room_id.clone(), root);
            }
        }
    }
}

async fn listen_room_keys(inner: Weak<Inner>) {
    let Some(client) = inner.upgrade().map(|inner| inner.client.clone()) else {
        return;
    };
    let Some(stream) = client.encryption().room_keys_received_stream().await else {
        return;
    };
    drop(client);
    pin_mut!(stream);
    while let Some(batch) = stream.next().await {
        let Ok(keys) = batch else {
            continue;
        };
        let Some(inner) = inner.upgrade() else {
            return;
        };
        inner.keys_arrived(keys.iter().map(|key| key.session_id.as_str()));
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use matrix_sdk::{
        ruma::{
            event_id, events::room::message::RedactedRoomMessageEventContent,
            events::AnyTimelineEvent, room_id, user_id, EventId, RoomId,
        },
        test_utils::mocks::MatrixMockServer,
    };
    use matrix_sdk_test::{event_factory::EventFactory, JoinedRoomBuilder, LeftRoomBuilder};
    use serde_json::json;
    use tokio::runtime::Handle;
    use wiremock::{
        matchers::{method, path_regex},
        Mock, ResponseTemplate,
    };

    use super::*;
    use crate::api::rooms::{LatestMessage, LatestMessageKind};
    use crate::test_support::{threaded_client, wait_until};

    fn thread(room: &str, root: &str, activity_ms: i64) -> RecentThread {
        RecentThread {
            room_id: room.into(),
            root_event_id: root.into(),
            root: LatestMessage {
                sender_name: "bob".into(),
                is_own: false,
                kind: LatestMessageKind::Text,
                body: Some("raiz".into()),
                timestamp_ms: 0,
            },
            latest_reply: None,
            reply_count: 1,
            activity_ms,
        }
    }

    #[test]
    fn upsert_orders_by_activity_replaces_the_same_root_and_keeps_ten() {
        let mut threads = Vec::new();
        for i in 0..12 {
            upsert(&mut threads, thread("!a:b.c", &format!("$r{i}"), i));
        }
        assert_eq!(threads.len(), MAX_THREADS);
        assert_eq!(threads[0].root_event_id, "$r11");
        assert_eq!(threads[9].root_event_id, "$r2");

        upsert(&mut threads, thread("!a:b.c", "$r2", 100));
        assert_eq!(threads.len(), MAX_THREADS);
        assert_eq!(threads[0].root_event_id, "$r2");
        assert_eq!(
            threads.iter().filter(|t| t.root_event_id == "$r2").count(),
            1
        );

        remove(&mut threads, "!a:b.c", "$r2");
        assert!(threads.iter().all(|t| t.root_event_id != "$r2"));
    }

    #[test]
    fn same_root_id_in_another_room_is_another_thread() {
        let mut threads = Vec::new();
        upsert(&mut threads, thread("!a:b.c", "$r", 1));
        upsert(&mut threads, thread("!b:b.c", "$r", 2));
        assert_eq!(threads.len(), 2);
    }

    #[test]
    fn most_recent_prefers_the_recency_stamp_then_the_latest_event() {
        let rooms = vec![
            ("sem nada", None, None),
            ("stamp 5", Some(5), Some(1)),
            ("ts 900", None, Some(900)),
            ("stamp 9", Some(9), None),
            ("ts 100", None, Some(100)),
        ];
        assert_eq!(
            most_recent(rooms, 4),
            vec!["stamp 9", "stamp 5", "ts 900", "ts 100"]
        );
    }

    #[test]
    fn encrypted_session_reads_the_megolm_session_id() {
        let f = EventFactory::new().room(room_id!("!a:b.c"));
        let encrypted = f
            .encrypted("cifra", "chave", "DEVICE", "sessao-1")
            .sender(user_id!("@bob:b.c"))
            .into_raw_sync();
        let plain = f
            .text_msg("oi")
            .sender(user_id!("@bob:b.c"))
            .into_raw_sync();
        assert_eq!(encrypted_session(&encrypted).as_deref(), Some("sessao-1"));
        assert_eq!(encrypted_session(&plain), None);
    }

    #[tokio::test]
    async fn read_thread_takes_count_and_latest_reply_from_the_bundled_summary() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let room = server.sync_joined_room(&client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let latest = f
            .text_msg("última")
            .sender(user_id!("@ana:b.c"))
            .event_id(event_id!("$r2"))
            .server_ts(2_000)
            .into_raw();
        let root = f
            .text_msg("raiz")
            .sender(user_id!("@bob:b.c"))
            .event_id(event_id!("$root"))
            .server_ts(1_000)
            .with_bundled_thread_summary(latest, 2, true)
            .into_event();

        let read = read_thread(&room, &root).await.expect("thread");

        assert_eq!(read.root, event_id!("$root"));
        assert_eq!(read.thread.room_id, "!a:b.c");
        assert_eq!(read.thread.root.body.as_deref(), Some("raiz"));
        assert_eq!(read.thread.reply_count, 2);
        let reply = read.thread.latest_reply.as_ref().expect("última resposta");
        assert_eq!(reply.body.as_deref(), Some("última"));
        assert_eq!(reply.sender_name, "ana");
        assert_eq!(read.thread.activity_ms, 2_000);
        assert!(read.missing_sessions.is_empty());
    }

    #[tokio::test]
    async fn read_thread_ignores_threads_without_my_participation_and_plain_events() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let room = server.sync_joined_room(&client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let latest = f.text_msg("r").sender(user_id!("@ana:b.c")).into_raw();
        let foreign = f
            .text_msg("raiz")
            .sender(user_id!("@bob:b.c"))
            .event_id(event_id!("$root"))
            .with_bundled_thread_summary(latest, 1, false)
            .into_event();
        let plain = f
            .text_msg("sem thread")
            .sender(user_id!("@bob:b.c"))
            .event_id(event_id!("$plain"))
            .into_event();

        assert!(read_thread(&room, &foreign).await.is_none());
        assert!(read_thread(&room, &plain).await.is_none());
    }

    #[tokio::test]
    async fn read_thread_keeps_an_undecryptable_latest_reply_and_asks_for_its_session() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let room = server.sync_joined_room(&client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let latest = f
            .encrypted("cifra", "chave", "DEVICE", "sessao-2")
            .sender(user_id!("@ana:b.c"))
            .server_ts(3_000)
            .into_raw();
        let root = f
            .text_msg("raiz")
            .sender(user_id!("@bob:b.c"))
            .event_id(event_id!("$root"))
            .with_bundled_thread_summary(latest, 1, true)
            .into_event();

        let read = read_thread(&room, &root).await.expect("thread");

        let reply = read.thread.latest_reply.expect("última resposta");
        assert_eq!(reply.kind, LatestMessageKind::Encrypted);
        assert_eq!(read.thread.activity_ms, 3_000);
        assert_eq!(read.missing_sessions, vec!["sessao-2".to_owned()]);
    }

    #[tokio::test]
    async fn read_thread_asks_for_the_session_of_an_undecryptable_root() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let room = server.sync_joined_room(&client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let latest = f
            .text_msg("r")
            .sender(user_id!("@ana:b.c"))
            .server_ts(3_000)
            .into_raw();
        let root = f
            .encrypted("cifra", "chave", "DEVICE", "sessao-raiz")
            .sender(user_id!("@bob:b.c"))
            .event_id(event_id!("$root"))
            .with_bundled_thread_summary(latest, 1, true)
            .into_event();

        let read = read_thread(&room, &root).await.expect("thread");

        assert_eq!(read.thread.root.kind, LatestMessageKind::Encrypted);
        assert_eq!(read.missing_sessions, vec!["sessao-raiz".to_owned()]);
    }

    fn root_with_summary(
        f: &EventFactory,
        root: &str,
        reply_ts: u64,
        participated: bool,
    ) -> Raw<AnyTimelineEvent> {
        let latest = f
            .text_msg(format!("resposta de {root}"))
            .sender(user_id!("@ana:b.c"))
            .server_ts(reply_ts)
            .into_raw();
        f.text_msg(format!("raiz {root}"))
            .sender(user_id!("@bob:b.c"))
            .event_id(&OwnedEventId::try_from(root).unwrap())
            .server_ts(1)
            .with_bundled_thread_summary(latest, 1, participated)
            .into_raw_timeline()
    }

    async fn mount_threads(
        server: &MatrixMockServer,
        room: &str,
        chunk: Vec<Raw<AnyTimelineEvent>>,
    ) {
        Mock::given(method("GET"))
            .and(path_regex(format!(r"/rooms/{}/threads$", room_path(room))))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({ "chunk": chunk })))
            .mount(server.server())
            .await;
    }

    // O id da sala pode ir no caminho com ou sem percent-encoding.
    fn room_path(room: &str) -> String {
        room.replace('.', r"\.")
            .replace('!', "(!|%21)")
            .replace(':', "(:|%3A)")
    }

    fn snapshots(
        threads: &RecentThreads,
    ) -> tokio::sync::mpsc::UnboundedReceiver<RecentThreadsSnapshot> {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        threads.watch(move |snapshot| tx.send(snapshot).is_ok());
        rx
    }

    async fn until(
        rx: &mut tokio::sync::mpsc::UnboundedReceiver<RecentThreadsSnapshot>,
        ready: impl Fn(&RecentThreadsSnapshot) -> bool,
    ) -> RecentThreadsSnapshot {
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let snapshot = rx.recv().await.expect("canal aberto");
                if ready(&snapshot) {
                    return snapshot;
                }
            }
        })
        .await
        .expect("snapshot em até 5 s")
    }

    fn summarized_root(
        f: &EventFactory,
        root: &EventId,
        reply_ts: u64,
        count: usize,
        participated: bool,
    ) -> TimelineEvent {
        f.text_msg("raiz")
            .sender(user_id!("@bob:b.c"))
            .event_id(root)
            .with_bundled_thread_summary(
                f.text_msg("r")
                    .sender(user_id!("@ana:b.c"))
                    .server_ts(reply_ts)
                    .into_raw(),
                count,
                participated,
            )
            .into_event()
    }

    #[tokio::test]
    async fn load_merges_the_rooms_orders_by_activity_and_marks_ready() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        for room in ["!a:b.c", "!b:b.c"] {
            server
                .sync_joined_room(&client, &OwnedRoomId::try_from(room).unwrap())
                .await;
        }
        let in_a = EventFactory::new().room(room_id!("!a:b.c"));
        let in_b = EventFactory::new().room(room_id!("!b:b.c"));
        mount_threads(
            &server,
            "!a:b.c",
            vec![root_with_summary(&in_a, "$a1", 100, true)],
        )
        .await;
        mount_threads(
            &server,
            "!b:b.c",
            vec![root_with_summary(&in_b, "$b1", 200, true)],
        )
        .await;
        let threads = RecentThreads::new(client, Handle::current());
        let mut rx = snapshots(&threads);

        threads.loader().load();
        let ready = until(&mut rx, |s| s.status == RecentThreadsStatus::Ready).await;

        let roots: Vec<_> = ready
            .threads
            .iter()
            .map(|t| t.root_event_id.as_str())
            .collect();
        assert_eq!(roots, vec!["$b1", "$a1"]);
    }

    #[tokio::test]
    async fn a_failing_room_is_left_out_and_all_failing_is_failed() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        server.sync_joined_room(&client, room_id!("!b:b.c")).await;
        let f = EventFactory::new().room(room_id!("!a:b.c"));
        mount_threads(
            &server,
            "!a:b.c",
            vec![root_with_summary(&f, "$a1", 100, true)],
        )
        .await;
        Mock::given(method("GET"))
            .and(path_regex(format!(
                r"/rooms/{}/threads$",
                room_path("!b:b.c")
            )))
            .respond_with(ResponseTemplate::new(500))
            .mount(server.server())
            .await;
        let threads = RecentThreads::new(client.clone(), Handle::current());
        let mut rx = snapshots(&threads);

        threads.loader().load();
        let ready = until(&mut rx, |s| s.status == RecentThreadsStatus::Ready).await;
        assert_eq!(ready.threads.len(), 1);

        server.server().reset().await;
        Mock::given(method("GET"))
            .and(path_regex(r"/threads$"))
            .respond_with(ResponseTemplate::new(500))
            .mount(server.server())
            .await;
        threads.loader().load();
        until(&mut rx, |s| s.status == RecentThreadsStatus::Failed).await;
    }

    #[tokio::test]
    async fn a_live_reply_in_my_thread_enters_even_from_a_room_outside_the_first_four() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!fora:b.c");
        let f = EventFactory::new().room(room_id);
        let root = event_id!("$raiz");
        server
            .mock_room_event()
            .room(room_id)
            .match_event_id()
            .ok(summarized_root(&f, root, 5_000, 3, true))
            .mount()
            .await;
        let threads = RecentThreads::new(client.clone(), Handle::current());
        let mut rx = snapshots(&threads);

        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_timeline_event(
                    f.text_msg("nova")
                        .sender(user_id!("@ana:b.c"))
                        .event_id(event_id!("$nova"))
                        .in_thread(root, root),
                ),
            )
            .await;

        let snapshot = until(&mut rx, |s| !s.threads.is_empty()).await;
        assert_eq!(snapshot.threads[0].root_event_id, "$raiz");
        assert_eq!(snapshot.threads[0].reply_count, 3);
    }

    #[tokio::test]
    async fn a_live_reply_in_someone_elses_thread_is_ignored() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let root = event_id!("$raiz");
        server
            .mock_room_event()
            .room(room_id)
            .match_event_id()
            .ok(summarized_root(&f, root, 1, 1, false))
            .expect(1)
            .mount()
            .await;
        let threads = RecentThreads::new(client.clone(), Handle::current());

        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_timeline_event(
                    f.text_msg("r")
                        .sender(user_id!("@ana:b.c"))
                        .in_thread(root, root),
                ),
            )
            .await;
        wait_until(|| async {
            let requests = server
                .server()
                .received_requests()
                .await
                .unwrap_or_default();
            requests.iter().any(|r| r.url.path().contains("/event/"))
                && threads.inner.refreshing.lock().unwrap().is_empty()
        })
        .await;

        assert!(threads.inner.snapshot.borrow().threads.is_empty());
    }

    #[tokio::test]
    async fn replies_during_a_refresh_cause_a_single_extra_refresh() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        server.sync_joined_room(&client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let root = event_id!("$raiz");
        let event = summarized_root(&f, root, 1, 1, true);
        Mock::given(method("GET"))
            .and(path_regex(r"/rooms/.*/event/"))
            .respond_with(
                ResponseTemplate::new(200)
                    .set_body_json(event.into_raw().json())
                    .set_delay(Duration::from_millis(200)),
            )
            .expect(2)
            .mount(server.server())
            .await;
        let threads = RecentThreads::new(client.clone(), Handle::current());

        for _ in 0..3 {
            threads.inner.refresh(room_id.to_owned(), root.to_owned());
        }
        wait_until(|| async { threads.inner.snapshot.borrow().threads.len() == 1 }).await;
        wait_until(|| async { threads.inner.refreshing.lock().unwrap().is_empty() }).await;
        // O expect(2) do wiremock confere no drop do servidor.
    }

    #[tokio::test]
    async fn a_root_redacted_on_refresh_leaves_the_list() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let room = server.sync_joined_room(&client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let root = event_id!("$raiz");
        let before = read_thread(&room, &summarized_root(&f, root, 1, 1, true))
            .await
            .expect("thread");
        server
            .mock_room_event()
            .room(room_id)
            .match_event_id()
            .ok(f
                .redacted(user_id!("@bob:b.c"), RedactedRoomMessageEventContent::new())
                .sender(user_id!("@bob:b.c"))
                .event_id(root)
                .with_bundled_thread_summary(
                    f.text_msg("r").sender(user_id!("@ana:b.c")).into_raw(),
                    1,
                    true,
                )
                .into_event())
            .expect(1)
            .mount()
            .await;
        let threads = RecentThreads::new(client, Handle::current());
        threads
            .inner
            .snapshot
            .send_modify(|snapshot| upsert(&mut snapshot.threads, before.thread));

        threads.inner.refresh(room_id.to_owned(), root.to_owned());

        wait_until(|| async { threads.inner.snapshot.borrow().threads.is_empty() }).await;
    }

    #[tokio::test]
    async fn a_live_redaction_of_a_listed_root_removes_the_thread() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let room = server.sync_joined_room(&client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let root = event_id!("$raiz");
        let before = read_thread(&room, &summarized_root(&f, root, 1, 1, true))
            .await
            .expect("thread");
        server
            .mock_room_event()
            .room(room_id)
            .match_event_id()
            .ok(f
                .redacted(user_id!("@bob:b.c"), RedactedRoomMessageEventContent::new())
                .sender(user_id!("@bob:b.c"))
                .event_id(root)
                .with_bundled_thread_summary(
                    f.text_msg("r").sender(user_id!("@ana:b.c")).into_raw(),
                    1,
                    true,
                )
                .into_event())
            .expect(1)
            .mount()
            .await;
        let threads = RecentThreads::new(client.clone(), Handle::current());
        threads
            .inner
            .snapshot
            .send_modify(|snapshot| upsert(&mut snapshot.threads, before.thread));

        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.redaction(root).sender(user_id!("@bob:b.c"))),
            )
            .await;

        wait_until(|| async { threads.inner.snapshot.borrow().threads.is_empty() }).await;
    }

    #[test]
    fn redacted_target_reads_both_redacts_locations() {
        let f = EventFactory::new().room(room_id!("!a:b.c"));
        let new = f
            .redaction(event_id!("$alvo"))
            .sender(user_id!("@bob:b.c"))
            .into_raw_sync();
        assert_eq!(redacted_target(&new), Some(event_id!("$alvo").to_owned()));
        let old = Raw::from_json_string(
            json!({"type": "m.room.redaction", "redacts": "$velho", "content": {}}).to_string(),
        )
        .unwrap();
        assert_eq!(redacted_target(&old), Some(event_id!("$velho").to_owned()));
        let other = f
            .text_msg("oi")
            .sender(user_id!("@bob:b.c"))
            .into_raw_sync();
        assert_eq!(redacted_target(&other), None);
    }

    #[tokio::test]
    async fn arriving_keys_refresh_the_roots_that_wait_for_them() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let root = event_id!("$raiz");
        server
            .mock_room_event()
            .room(room_id)
            .match_event_id()
            .ok(summarized_root(&f, root, 1, 1, true))
            .expect(1)
            .mount()
            .await;
        server.sync_joined_room(&client, room_id).await;
        let threads = RecentThreads::new(client, Handle::current());
        threads
            .inner
            .waiting_keys
            .lock()
            .unwrap()
            .entry("sessao-1".into())
            .or_default()
            .insert((room_id.to_owned(), root.to_owned()));

        threads.inner.keys_arrived(["outra", "sessao-1"]);

        wait_until(|| async { threads.inner.snapshot.borrow().threads.len() == 1 }).await;
        assert!(threads.inner.waiting_keys.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn dropping_the_service_aborts_a_refresh_in_progress() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        server.sync_joined_room(&client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let root = event_id!("$raiz");
        Mock::given(method("GET"))
            .and(path_regex(r"/rooms/.*/event/"))
            .respond_with(
                ResponseTemplate::new(200)
                    .set_body_json(summarized_root(&f, root, 1, 1, true).into_raw().json())
                    .set_delay(Duration::from_secs(3)),
            )
            .mount(server.server())
            .await;
        let threads = RecentThreads::new(client, Handle::current());
        let inner = Arc::downgrade(&threads.inner);
        threads.inner.refresh(room_id.to_owned(), root.to_owned());
        wait_until(|| async {
            let requests = server
                .server()
                .received_requests()
                .await
                .unwrap_or_default();
            requests.iter().any(|r| r.url.path().contains("/event/"))
        })
        .await;

        drop(threads);

        // Bem antes do atraso de 3 s: só o abort solta o Inner (e o Client) a tempo.
        tokio::time::timeout(Duration::from_secs(1), async {
            while inner.strong_count() > 0 {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .expect("Inner solto depois do drop");
    }

    #[tokio::test]
    async fn a_session_is_asked_to_the_backup_only_once() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let room = server.sync_joined_room(&client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let latest = f
            .encrypted("cifra", "chave", "DEVICE", "sessao-2")
            .sender(user_id!("@ana:b.c"))
            .into_raw();
        let root = f
            .text_msg("raiz")
            .sender(user_id!("@bob:b.c"))
            .event_id(event_id!("$root"))
            .with_bundled_thread_summary(latest, 1, true)
            .into_event();
        let read = read_thread(&room, &root).await.expect("thread");
        let threads = RecentThreads::new(client, Handle::current());

        assert_eq!(
            threads.inner.sessions_to_download(&room, &read),
            vec!["sessao-2".to_owned()]
        );
        // A chave chegou mas não decifrou: a recarga volta a esperar sem pedir de novo.
        threads.inner.keys_arrived(["sessao-2"]);
        assert!(threads.inner.sessions_to_download(&room, &read).is_empty());
        assert!(threads.inner.waiting_keys.lock().unwrap()["sessao-2"]
            .contains(&(room_id.to_owned(), event_id!("$root").to_owned())));
    }

    fn root_with_latest(f: &EventFactory, root: &EventId, latest: &EventId, body: &str) -> TimelineEvent {
        f.text_msg("raiz")
            .sender(user_id!("@bob:b.c"))
            .event_id(root)
            .with_bundled_thread_summary(
                f.text_msg(body)
                    .sender(user_id!("@ana:b.c"))
                    .event_id(latest)
                    .server_ts(2_000)
                    .into_raw(),
                1,
                true,
            )
            .into_event()
    }

    async fn listed_thread(
        server: &MatrixMockServer,
        client: &Client,
        room_id: &RoomId,
    ) -> RecentThreads {
        let room = server.sync_joined_room(client, room_id).await;
        let f = EventFactory::new().room(room_id);
        let read = read_thread(
            &room,
            &root_with_latest(&f, event_id!("$raiz"), event_id!("$r1"), "antiga"),
        )
        .await
        .expect("thread");
        let threads = RecentThreads::new(client.clone(), Handle::current());
        threads.inner.apply(&room, &read);
        threads
    }

    fn latest_body(threads: &RecentThreads) -> Option<String> {
        threads.inner.snapshot.borrow().threads.first()?.latest_reply.as_ref()?.body.clone()
    }

    #[tokio::test]
    async fn redacting_the_latest_reply_refreshes_the_thread() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let threads = listed_thread(&server, &client, room_id).await;
        server
            .mock_room_event()
            .room(room_id)
            .match_event_id()
            .ok(root_with_latest(&f, event_id!("$raiz"), event_id!("$r0"), "anterior"))
            .expect(1)
            .mount()
            .await;

        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.redaction(event_id!("$r1")).sender(user_id!("@ana:b.c"))),
            )
            .await;

        wait_until(|| async { latest_body(&threads).as_deref() == Some("anterior") }).await;
    }

    #[tokio::test]
    async fn editing_the_latest_reply_refreshes_the_thread() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let threads = listed_thread(&server, &client, room_id).await;
        server
            .mock_room_event()
            .room(room_id)
            .match_event_id()
            .ok(root_with_latest(&f, event_id!("$raiz"), event_id!("$r1"), "editada"))
            .expect(1)
            .mount()
            .await;
        let edit: Raw<AnySyncTimelineEvent> = Raw::from_json_string(
            json!({
                "type": "m.room.message",
                "event_id": "$edicao",
                "sender": "@ana:b.c",
                "origin_server_ts": 3_000,
                "content": {
                    "msgtype": "m.text",
                    "body": "* editada",
                    "m.new_content": { "msgtype": "m.text", "body": "editada" },
                    "m.relates_to": { "rel_type": "m.replace", "event_id": "$r1" }
                }
            })
            .to_string(),
        )
        .unwrap();

        server
            .sync_room(&client, JoinedRoomBuilder::new(room_id).add_timeline_event(edit))
            .await;

        wait_until(|| async { latest_body(&threads).as_deref() == Some("editada") }).await;
    }

    #[test]
    fn edited_target_reads_only_replacements() {
        let edit: Raw<AnySyncTimelineEvent> = Raw::from_json_string(
            json!({
                "type": "m.room.message",
                "content": {
                    "body": "* x",
                    "m.relates_to": { "rel_type": "m.replace", "event_id": "$alvo" }
                }
            })
            .to_string(),
        )
        .unwrap();
        assert_eq!(edited_target(&edit), Some(event_id!("$alvo").to_owned()));
        let thread_reply: Raw<AnySyncTimelineEvent> = Raw::from_json_string(
            json!({
                "type": "m.room.message",
                "content": {
                    "body": "r",
                    "m.relates_to": { "rel_type": "m.thread", "event_id": "$raiz" }
                }
            })
            .to_string(),
        )
        .unwrap();
        assert_eq!(edited_target(&thread_reply), None);
    }

    #[tokio::test]
    async fn leaving_a_room_drops_its_threads() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let threads = listed_thread(&server, &client, room_id).await;
        assert_eq!(threads.inner.snapshot.borrow().threads.len(), 1);

        server
            .sync_room(&client, LeftRoomBuilder::new(room_id))
            .await;

        wait_until(|| async { threads.inner.snapshot.borrow().threads.is_empty() }).await;
    }

    #[tokio::test]
    async fn sync_unavailable_before_the_first_load_marks_failed() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let threads = RecentThreads::new(client, Handle::current());

        threads.loader().sync_unavailable();
        assert_eq!(
            threads.inner.snapshot.borrow().status,
            RecentThreadsStatus::Failed
        );

        threads
            .inner
            .snapshot
            .send_modify(|snapshot| snapshot.status = RecentThreadsStatus::Loading);
        threads.inner.load_started.store(true, Ordering::SeqCst);
        threads.loader().sync_unavailable();
        assert_eq!(
            threads.inner.snapshot.borrow().status,
            RecentThreadsStatus::Loading
        );
    }

    #[tokio::test]
    async fn a_lagged_update_channel_loads_again() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let threads = RecentThreads::new(client, Handle::current());
        let (sender, receiver) = broadcast::channel(1);
        for _ in 0..3 {
            sender.send(RoomUpdates::default()).unwrap();
        }

        threads
            .inner
            .spawn(listen_updates(Arc::downgrade(&threads.inner), receiver));

        wait_until(|| async { threads.inner.load_started.load(Ordering::SeqCst) }).await;
    }
}
