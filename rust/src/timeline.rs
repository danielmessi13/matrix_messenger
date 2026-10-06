use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, Mutex},
    time::Duration,
};

use eyeball_im::Vector;
use futures_util::pin_mut;
use matrix_sdk::{
    ruma::{
        api::client::receipt::create_receipt::v3::ReceiptType,
        events::room::message::{MessageType, RoomMessageEventContent},
        EventId, OwnedEventId, OwnedUserId, UserId,
    },
    send_queue::SendHandle,
    Room,
};
use matrix_sdk_ui::timeline::{
    EventSendState, EventTimelineItem, MsgLikeKind, Profile, Timeline, TimelineBuilder,
    TimelineDetails, TimelineFocus, TimelineItem, TimelineItemContent,
    TimelineReadReceiptTracking, TimelineUniqueId, VirtualTimelineItem,
};
use tokio::{runtime::Handle, task::AbortHandle};

use crate::{
    api::timeline::{
        MessageKind, ReplyPreview, ReplyState, SendState, ThreadInfo, TimelineEntry, TimelineError, TimelineErrorKind,
        TimelineMessage, TimelineSnapshot,
    },
    diff_window::next_batch_or,
    threads::{changed_in, unread_by_thread, ThreadReads},
};

const PAGE_EVENTS: u16 = 20;

const THREAD_PAGES: usize = 5;

const RECEIPT_ECHO_TIMEOUT: Duration = Duration::from_secs(30);

pub(crate) struct TimelineHandle {
    timeline: Arc<Timeline>,
    room: Room,
    own_user: OwnedUserId,
    thread_root: Option<OwnedEventId>,
    reads: ThreadReads,
    runtime: Handle,
    tasks: Mutex<Vec<AbortHandle>>,
}

impl TimelineHandle {
    pub(crate) async fn open(
        room: Room,
        thread_root: Option<OwnedEventId>,
        reads: ThreadReads,
        runtime: Handle,
    ) -> Result<Self, TimelineError> {
        let focus = match thread_root.clone() {
            Some(root_event_id) => TimelineFocus::Thread { root_event_id },
            None => TimelineFocus::Live { hide_threaded_events: true },
        };
        // O padrão do builder não acompanha recibos; sem isso o "Lida por" fica vazio.
        let timeline = TimelineBuilder::new(&room)
            .with_focus(focus)
            .track_read_marker_and_receipts(TimelineReadReceiptTracking::MessageLikeEvents)
            .build()
            .await?;
        if timeline.is_threaded() {
            // A timeline de thread só lê o cache; respostas que não vieram pelo sync desta sessão estão no servidor.
            for _ in 0..THREAD_PAGES {
                match timeline.paginate_backwards(PAGE_EVENTS).await {
                    Ok(false) => {}
                    Ok(true) => break,
                    Err(error) => {
                        log::warn!("falha ao paginar a thread: {error}");
                        break;
                    }
                }
            }
        }
        let handle = Self {
            timeline: Arc::new(timeline),
            own_user: room.own_user_id().to_owned(),
            thread_root,
            room,
            reads,
            runtime,
            tasks: Mutex::default(),
        };
        if let Some(root) = handle.thread_root.clone() {
            handle.watch_thread_reads(root);
        }
        Ok(handle)
    }

    fn watch_thread_reads(&self, root: OwnedEventId) {
        let room = self.room.clone();
        let reads = self.reads.clone();
        let task = self.runtime.spawn(async move {
            let client = room.client();
            let Ok((thread, _drop_handles)) = client.event_cache().thread(room.room_id(), &root).await
            else {
                return;
            };
            let Ok(mut info) = thread.subscribe_to_thread_info().await else {
                return;
            };
            while info.next().await.is_some() {
                reads.notify(room.room_id());
            }
        });
        self.tasks.lock().unwrap().push(task.abort_handle());
    }

    pub(crate) fn watch(&self, mut emit: impl FnMut(TimelineSnapshot) -> bool + Send + 'static) {
        let timeline = self.timeline.clone();
        let room = self.room.clone();
        let own_user = self.own_user.clone();
        let thread_root = self.thread_root.clone();
        let reads = self.reads.clone();
        let task = self.runtime.spawn(async move {
            // Só a conversa principal escuta, inscrita antes do primeiro snapshot para não perder aviso.
            let mut changed = thread_root.is_none().then(|| reads.subscribe());
            let (mut items, stream) = timeline.subscribe().await;
            pin_mut!(stream);
            let mut fetched = HashSet::new();
            loop {
                fetch_missing_replies(&timeline, &items, &mut fetched);
                let unread = match thread_root {
                    Some(_) => HashMap::new(),
                    None => unread_by_thread(&room).await,
                };
                if !emit(snapshot(&items, &own_user, thread_root.as_deref(), &unread)) {
                    return;
                }
                let signal = async {
                    match changed.as_mut() {
                        Some(changed) => changed_in(changed, room.room_id()).await,
                        None => std::future::pending().await,
                    }
                };
                if !next_batch_or(&mut stream, &mut items, signal).await {
                    return;
                }
            }
        });
        self.tasks.lock().unwrap().push(task.abort_handle());
    }

    pub(crate) async fn paginate_backwards(&self) -> Result<bool, TimelineError> {
        Ok(self.timeline.paginate_backwards(PAGE_EVENTS).await?)
    }

    pub(crate) async fn send_markdown(&self, body: String) -> Result<(), TimelineError> {
        self.timeline
            .send(RoomMessageEventContent::text_markdown(body).into())
            .await?;
        Ok(())
    }

    // Qualquer falha de envio desliga a fila da sala no SDK; sem religar, nada mais sai.
    pub(crate) async fn retry(&self, item_id: &str) -> Result<(), TimelineError> {
        let handle = self.send_handle(item_id).await?;
        self.room.send_queue().set_enabled(true);
        handle
            .unwedge()
            .await
            .map_err(|error| TimelineError::new(TimelineErrorKind::Unknown, error.to_string()))
    }

    pub(crate) async fn cancel(&self, item_id: &str) -> Result<(), TimelineError> {
        self.send_handle(item_id)
            .await?
            .abort()
            .await
            .map_err(|error| TimelineError::new(TimelineErrorKind::Unknown, error.to_string()))?;
        self.room.send_queue().set_enabled(true);
        Ok(())
    }

    // O SDK escolhe o recibo pelo foco: `main` na conversa principal, a raiz na thread.
    pub(crate) async fn mark_as_read(&self) -> Result<(), TimelineError> {
        // Inscrito antes do recibo para não perder a mudança que ele causa.
        let echo = match &self.thread_root {
            Some(root) => {
                let client = self.room.client();
                match client.event_cache().thread(self.room.room_id(), root).await {
                    Ok((thread, drop_handles)) => {
                        thread.subscribe_to_thread_info().await.ok().map(|info| (info, drop_handles))
                    }
                    Err(_) => None,
                }
            }
            None => None,
        };
        self.timeline.mark_as_read(ReceiptType::Read).await?;
        if let Some((mut info, drop_handles)) = echo {
            let reads = self.reads.clone();
            let room_id = self.room.room_id().to_owned();
            // Fora de `tasks` de propósito: recolher a thread solta o handle, mas o eco do recibo ainda precisa avisar.
            self.runtime.spawn(async move {
                let _drop_handles = drop_handles;
                let _ = tokio::time::timeout(RECEIPT_ECHO_TIMEOUT, info.next()).await;
                reads.notify(&room_id);
            });
        }
        Ok(())
    }

    pub(crate) async fn open_thread(&self, root_event_id: &str) -> Result<Self, TimelineError> {
        let root = OwnedEventId::try_from(root_event_id).map_err(|error| {
            TimelineError::new(TimelineErrorKind::MessageNotFound, error.to_string())
        })?;
        Self::open(self.room.clone(), Some(root), self.reads.clone(), self.runtime.clone()).await
    }

    async fn send_handle(&self, item_id: &str) -> Result<SendHandle, TimelineError> {
        self.timeline
            .items()
            .await
            .iter()
            .find(|item| item.unique_id().0 == item_id)
            .and_then(|item| item.as_event()?.local_echo_send_handle())
            .ok_or_else(|| {
                TimelineError::new(TimelineErrorKind::MessageNotFound, item_id.to_owned())
            })
    }

    #[cfg(test)]
    fn live_tasks(&self) -> usize {
        self.tasks.lock().unwrap().iter().filter(|task| !task.is_finished()).count()
    }
}

impl Drop for TimelineHandle {
    fn drop(&mut self) {
        for task in self.tasks.get_mut().unwrap().drain(..) {
            task.abort();
        }
    }
}

fn profile_name(sender: &UserId, profile: &TimelineDetails<Profile>) -> String {
    match profile {
        TimelineDetails::Ready(Profile { display_name: Some(name), .. }) if !name.is_empty() => {
            name.clone()
        }
        _ => sender.localpart().to_owned(),
    }
}

fn kind_and_body(content: &TimelineItemContent) -> Option<(MessageKind, Option<String>)> {
    let msglike = content.as_msglike()?;
    Some(match &msglike.kind {
        MsgLikeKind::Message(message) => match message.msgtype() {
            MessageType::Text(text) => (MessageKind::Text, Some(text.body.clone())),
            MessageType::Notice(notice) => (MessageKind::Notice, Some(notice.body.clone())),
            MessageType::Emote(emote) => (MessageKind::Emote, Some(emote.body.clone())),
            MessageType::Image(_) => (MessageKind::Image, None),
            MessageType::File(_) | MessageType::Video(_) | MessageType::Audio(_) => {
                (MessageKind::File, None)
            }
            _ => (MessageKind::Other, None),
        },
        MsgLikeKind::UnableToDecrypt(_) => (MessageKind::Encrypted, None),
        MsgLikeKind::Redacted => (MessageKind::Redacted, None),
        _ => (MessageKind::Other, None),
    })
}

fn send_state(item: &EventTimelineItem) -> SendState {
    match item.send_state() {
        None | Some(EventSendState::Sent { .. }) => SendState::Sent,
        Some(EventSendState::NotSentYet { .. }) => SendState::Sending,
        Some(EventSendState::SendingFailed { is_recoverable: true, .. }) => SendState::Failed,
        Some(EventSendState::SendingFailed { is_recoverable: false, .. }) => SendState::Rejected,
    }
}

// O SDK só preenche a mensagem respondida se ela já estiver na timeline; as outras são buscadas uma vez.
fn fetch_missing_replies(
    timeline: &Arc<Timeline>,
    items: &Vector<Arc<TimelineItem>>,
    fetched: &mut HashSet<OwnedEventId>,
) {
    for event in items.iter().filter_map(|item| item.as_event()) {
        let Some(reply) = event.content().in_reply_to() else {
            continue;
        };
        let Some(event_id) = event.event_id() else {
            continue;
        };
        if !matches!(reply.event, TimelineDetails::Unavailable) || !fetched.insert(event_id.to_owned()) {
            continue;
        }
        let timeline = timeline.clone();
        let event_id = event_id.to_owned();
        tokio::spawn(async move {
            if let Err(error) = timeline.fetch_details_for_event(&event_id).await {
                log::warn!("falha ao buscar a mensagem respondida: {error}");
            }
        });
    }
}

fn reply_preview(item: &EventTimelineItem) -> Option<ReplyPreview> {
    let reply = item.content().in_reply_to()?;
    Some(match &reply.event {
        TimelineDetails::Ready(event) => {
            let (kind, body) = kind_and_body(&event.content).unwrap_or((MessageKind::Other, None));
            ReplyPreview {
                state: ReplyState::Ready,
                sender_name: Some(profile_name(&event.sender, &event.sender_profile)),
                kind: Some(kind),
                body,
            }
        }
        TimelineDetails::Error(_) => {
            ReplyPreview { state: ReplyState::Unavailable, sender_name: None, kind: None, body: None }
        }
        TimelineDetails::Unavailable | TimelineDetails::Pending => {
            ReplyPreview { state: ReplyState::Loading, sender_name: None, kind: None, body: None }
        }
    })
}

fn thread_info(item: &EventTimelineItem, unread: &HashMap<OwnedEventId, u32>) -> Option<ThreadInfo> {
    let summary = item.content().thread_summary()?;
    let (latest_sender, latest_timestamp_ms) = match &summary.latest_event {
        TimelineDetails::Ready(event) => (
            Some(profile_name(&event.sender, &event.sender_profile)),
            Some(i64::from(event.timestamp.0)),
        ),
        _ => (None, None),
    };
    Some(ThreadInfo {
        root_event_id: item.event_id()?.to_string(),
        replies: summary.num_replies,
        latest_sender,
        latest_timestamp_ms,
        unread: item.event_id().and_then(|id| unread.get(id)).copied().unwrap_or(0),
    })
}

// O unique_id passa do eco local para o evento confirmado; o event_id e o transaction_id não.
fn message(
    id: &TimelineUniqueId,
    item: &EventTimelineItem,
    unread: &HashMap<OwnedEventId, u32>,
) -> Option<TimelineMessage> {
    let (kind, body) = kind_and_body(item.content())?;
    Some(TimelineMessage {
        id: id.0.clone(),
        sender_id: item.sender().to_string(),
        sender_name: profile_name(item.sender(), item.sender_profile()),
        is_own: item.is_own(),
        timestamp_ms: i64::from(item.timestamp().0),
        kind,
        body,
        edited: item.content().as_message().is_some_and(|message| message.is_edited()),
        send_state: send_state(item),
        thread: thread_info(item, unread),
        reply_to: reply_preview(item),
        read_by: Vec::new(),
    })
}

// Ao chegar ao início, a timeline de thread inclui a raiz, que já aparece na conversa principal.
pub(crate) fn snapshot(
    items: &Vector<Arc<TimelineItem>>,
    own_user: &UserId,
    thread_root: Option<&EventId>,
    unread: &HashMap<OwnedEventId, u32>,
) -> TimelineSnapshot {
    let mut names: HashMap<OwnedUserId, String> = HashMap::new();
    let mut entries = Vec::new();
    let mut reached_start = false;
    let mut last_read: Option<(usize, Vec<OwnedUserId>)> = None;
    for item in items {
        if let Some(event) = item.as_event() {
            if thread_root.is_some() && event.event_id() == thread_root {
                continue;
            }
            names.insert(
                event.sender().to_owned(),
                profile_name(event.sender(), event.sender_profile()),
            );
            let message = message(item.unique_id(), event, unread);
            if message.is_some() && event.is_own() {
                last_read = Some((entries.len(), Vec::new()));
            }
            // O recibo de quem responde passa para a resposta dele; quem leu algo depois leu a minha.
            if let Some((_, readers)) = last_read.as_mut() {
                for user in event.read_receipts().keys() {
                    if user.as_str() != own_user.as_str() && !readers.contains(user) {
                        readers.push(user.clone());
                    }
                }
            }
            let Some(message) = message else {
                continue;
            };
            entries.push(TimelineEntry { date_divider_ms: None, message: Some(message) });
        } else if let Some(virtual_item) = item.as_virtual() {
            match virtual_item {
                VirtualTimelineItem::DateDivider(day) => entries.push(TimelineEntry {
                    date_divider_ms: Some(i64::from(day.0)),
                    message: None,
                }),
                VirtualTimelineItem::TimelineStart => reached_start = true,
                VirtualTimelineItem::ReadMarker => {}
            }
        }
    }
    if let Some((index, readers)) = last_read {
        if let Some(message) = entries[index].message.as_mut() {
            message.read_by = readers
                .iter()
                .map(|user| names.get(user).cloned().unwrap_or_else(|| user.localpart().to_owned()))
                .collect();
        }
    }
    TimelineSnapshot { items: entries, reached_start }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use matrix_sdk::{
        ruma::{
            api::client::receipt::create_receipt::v3::ReceiptType,
            event_id,
            events::receipt::{ReceiptThread, ReceiptType as EventReceiptType},
            room_id, user_id,
        },
        test_utils::mocks::{
            MatrixMockServer, RoomMessagesResponseTemplate, RoomRelationsResponseTemplate,
        },
    };
    use matrix_sdk_test::{event_factory::EventFactory, JoinedRoomBuilder};
    use serde_json::json;
    use tokio::runtime::Handle;

    use super::*;
    use crate::{test_support::threaded_client, threads::ThreadReads};

    fn messages(snapshot: &TimelineSnapshot) -> Vec<&TimelineMessage> {
        snapshot.items.iter().filter_map(|entry| entry.message.as_ref()).collect()
    }

    async fn wait_for(
        handle: &TimelineHandle,
        ready: impl Fn(&TimelineSnapshot) -> bool,
    ) -> TimelineSnapshot {
        // O reenvio do SDK espera até ~1,5 s entre tentativas de um 500.
        for _ in 0..500 {
            let current = snapshot(
                &handle.timeline.items().await,
                &handle.own_user,
                handle.thread_root.as_deref(),
                &HashMap::new(),
            );
            if ready(&current) {
                return current;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        panic!(
            "{:#?}",
            snapshot(
                &handle.timeline.items().await,
                &handle.own_user,
                handle.thread_root.as_deref(),
                &HashMap::new()
            )
        );
    }

    async fn client(server: &MatrixMockServer) -> matrix_sdk::Client {
        threaded_client(server).await
    }

    #[tokio::test]
    async fn snapshot_converts_kinds_hides_thread_replies_and_marks_read_by() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let own = client.user_id().unwrap().to_owned();
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("**oi**").sender(bob).event_id(event_id!("$1")))
                    .add_timeline_event(f.notice("aviso").sender(bob).event_id(event_id!("$2")))
                    .add_timeline_event(f.text_msg("raiz").sender(bob).event_id(event_id!("$root")))
                    .add_timeline_event(
                        f.text_msg("resposta")
                            .sender(bob)
                            .event_id(event_id!("$r1"))
                            .in_thread(event_id!("$root"), event_id!("$root")),
                    )
                    .add_timeline_event(f.text_msg("minha").sender(&own).event_id(event_id!("$3")))
                    .add_receipt(
                        f.read_receipts()
                            .add(event_id!("$3"), bob, EventReceiptType::Read, ReceiptThread::Unthreaded)
                            .into_event(),
                    ),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        let current = wait_for(&handle, |s| messages(s).len() >= 4).await;

        let all = messages(&current);
        assert!(all.iter().all(|m| m.body.as_deref() != Some("resposta")));
        let first = all.iter().find(|m| m.body.as_deref() == Some("**oi**")).unwrap();
        assert_eq!((first.kind, first.body.as_deref()), (MessageKind::Text, Some("**oi**")));
        assert_eq!(first.sender_name, "bob");
        assert!(!first.is_own);
        assert_eq!(all.iter().find(|m| m.body.as_deref() == Some("aviso")).unwrap().kind, MessageKind::Notice);
        let root = all.iter().find(|m| m.body.as_deref() == Some("raiz")).unwrap();
        let thread = root.thread.as_ref().expect("resumo da thread");
        assert_eq!((thread.root_event_id.as_str(), thread.replies), ("$root", 1));
        let mine = all.iter().find(|m| m.body.as_deref() == Some("minha")).unwrap();
        assert!(mine.is_own);
        assert_eq!(mine.read_by, vec!["bob".to_owned()]);
        assert!(all.iter().filter(|m| m.body.as_deref() != Some("minha")).all(|m| m.read_by.is_empty()));
        assert!(current.items.iter().any(|entry| entry.date_divider_ms.is_some()));
    }

    #[tokio::test]
    async fn thread_timeline_has_only_the_replies() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("raiz").sender(bob).event_id(event_id!("$root")))
                    .add_timeline_event(
                        f.text_msg("resposta")
                            .sender(bob)
                            .event_id(event_id!("$r1"))
                            .in_thread(event_id!("$root"), event_id!("$root")),
                    ),
            )
            .await;
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        let thread = main.open_thread("$root").await.unwrap();
        let current = wait_for(&thread, |s| !messages(s).is_empty()).await;

        let bodies: Vec<_> = messages(&current).iter().map(|m| m.body.clone()).collect();
        assert_eq!(bodies, vec![Some("resposta".to_owned())]);
    }

    #[tokio::test]
    async fn paginate_backwards_reaches_the_start() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("nova").sender(bob).event_id(event_id!("$n")))
                    .set_timeline_limited()
                    .set_timeline_prev_batch("prev"),
            )
            .await;
        server
            .mock_room_messages()
            .ok(RoomMessagesResponseTemplate::default().events(vec![f
                .text_msg("antiga")
                .sender(bob)
                .event_id(event_id!("$o"))
                .into_raw_timeline()]))
            .mount()
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        let reached = handle.paginate_backwards().await.unwrap();
        let current = wait_for(&handle, |s| messages(s).len() >= 2 && s.reached_start).await;

        assert!(reached);
        assert_eq!(messages(&current)[0].body.as_deref(), Some("antiga"));
    }

    #[tokio::test]
    async fn send_markdown_shows_local_echo_until_sent() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        server.mock_room_state_encryption().plain().mount().await;
        server.mock_room_send().ok(event_id!("$sent")).mount().await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        handle.send_markdown("**negrito**".to_owned()).await.unwrap();
        let current = wait_for(&handle, |s| {
            messages(s).iter().any(|m| m.send_state == SendState::Sent)
        })
        .await;

        let sent = messages(&current)[0];
        assert!(sent.is_own);
        assert_eq!(sent.body.as_deref(), Some("**negrito**"));
        let content = RoomMessageEventContent::text_markdown("**negrito**");
        assert!(matches!(content.msgtype, MessageType::Text(text) if text.formatted.is_some()));
    }

    #[tokio::test]
    async fn own_message_keeps_its_id_when_the_server_echoes_it() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let own = client.user_id().unwrap().to_owned();
        let room_id = room_id!("!a:b.c");
        let room = server.sync_joined_room(&client, room_id).await;
        server.mock_room_state_encryption().plain().mount().await;
        server.mock_room_send().ok(event_id!("$sent")).mount().await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();
        handle.send_markdown("oi".to_owned()).await.unwrap();
        let local = wait_for(&handle, |s| messages(s).len() == 1).await;
        let local_id = messages(&local)[0].id.clone();

        let f = EventFactory::new().room(room_id);
        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("oi").sender(&own).event_id(event_id!("$sent"))),
            )
            .await;
        for _ in 0..500 {
            let items = handle.timeline.items().await;
            if items.iter().filter_map(|item| item.as_event()).any(|event| !event.is_local_echo()) {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        let remote = wait_for(&handle, |s| messages(s).len() == 1).await;

        let items = handle.timeline.items().await;
        assert!(items.iter().filter_map(|item| item.as_event()).all(|event| !event.is_local_echo()));
        assert_eq!(messages(&remote)[0].id, local_id);
    }

    #[tokio::test]
    async fn rejected_send_can_be_cancelled() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        server.mock_room_state_encryption().plain().mount().await;
        server
            .mock_room_send()
            .respond_with(
                wiremock::ResponseTemplate::new(403)
                    .set_body_json(json!({ "errcode": "M_FORBIDDEN", "error": "sem permissão" })),
            )
            .mount()
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        handle.send_markdown("oi".to_owned()).await.unwrap();
        let current = wait_for(&handle, |s| {
            messages(s).iter().any(|m| m.send_state == SendState::Rejected)
        })
        .await;
        let id = messages(&current)[0].id.clone();
        handle.cancel(&id).await.unwrap();

        wait_for(&handle, |s| messages(s).is_empty()).await;
        let missing = handle.retry(&id).await.unwrap_err();
        assert_eq!(missing.kind, TimelineErrorKind::MessageNotFound);
    }

    #[tokio::test]
    async fn retry_after_recoverable_failure_sends_the_message() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        server.mock_room_state_encryption().plain().mount().await;
        // 5xx é `Transient` para o SDK: o envio vira SendingFailed { is_recoverable: true }.
        let failing = server.mock_room_send().error500().mount_as_scoped().await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        handle.send_markdown("oi".to_owned()).await.unwrap();
        let current = wait_for(&handle, |s| {
            messages(s).iter().any(|m| m.send_state == SendState::Failed)
        })
        .await;
        drop(failing);
        server.mock_room_send().ok(event_id!("$sent")).mount().await;
        handle.retry(&messages(&current)[0].id).await.unwrap();

        wait_for(&handle, |s| messages(s).iter().any(|m| m.send_state == SendState::Sent)).await;
    }

    #[tokio::test]
    async fn cancel_after_rejection_lets_the_next_message_be_sent() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        server.mock_room_state_encryption().plain().mount().await;
        let forbidden = server
            .mock_room_send()
            .respond_with(
                wiremock::ResponseTemplate::new(403)
                    .set_body_json(json!({ "errcode": "M_FORBIDDEN", "error": "sem permissão" })),
            )
            .mount_as_scoped()
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        handle.send_markdown("um".to_owned()).await.unwrap();
        let current = wait_for(&handle, |s| {
            messages(s).iter().any(|m| m.send_state == SendState::Rejected)
        })
        .await;
        handle.cancel(&messages(&current)[0].id).await.unwrap();
        wait_for(&handle, |s| messages(s).is_empty()).await;
        drop(forbidden);
        server.mock_room_send().ok(event_id!("$sent")).mount().await;
        handle.send_markdown("dois".to_owned()).await.unwrap();

        let current = wait_for(&handle, |s| {
            messages(s).iter().any(|m| m.send_state == SendState::Sent)
        })
        .await;
        assert_eq!(messages(&current)[0].body.as_deref(), Some("dois"));
    }

    #[tokio::test]
    async fn open_thread_fetches_replies_from_the_server() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("raiz").sender(bob).event_id(event_id!("$root"))),
            )
            .await;
        server
            .mock_room_relations()
            .match_target_event(event_id!("$root").to_owned())
            .ok(RoomRelationsResponseTemplate::default().events(vec![f
                .text_msg("antiga")
                .sender(bob)
                .event_id(event_id!("$r1"))
                .in_thread(event_id!("$root"), event_id!("$root"))
                .into_raw_timeline()]))
            .mount()
            .await;
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        let thread = main.open_thread("$root").await.unwrap();
        let current = wait_for(&thread, |s| !messages(s).is_empty()).await;

        let bodies: Vec<_> = messages(&current).iter().map(|m| m.body.clone()).collect();
        assert_eq!(bodies, vec![Some("antiga".to_owned())]);
    }

    async fn room_with_thread(server: &MatrixMockServer, client: &matrix_sdk::Client) -> Room {
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        server
            .sync_room(
                client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("raiz").sender(bob).event_id(event_id!("$root")))
                    .add_timeline_event(
                        f.text_msg("resposta")
                            .sender(bob)
                            .event_id(event_id!("$r1"))
                            .in_thread(event_id!("$root"), event_id!("$root")),
                    ),
            )
            .await
    }

    async fn recv_until(
        rx: &mut tokio::sync::mpsc::UnboundedReceiver<TimelineSnapshot>,
        ready: impl Fn(&TimelineSnapshot) -> bool,
    ) -> TimelineSnapshot {
        loop {
            let current =
                tokio::time::timeout(Duration::from_secs(5), rx.recv()).await.unwrap().unwrap();
            if ready(&current) {
                return current;
            }
        }
    }

    fn root_unread(snapshot: &TimelineSnapshot) -> Option<u32> {
        messages(snapshot)
            .into_iter()
            .find(|m| m.body.as_deref() == Some("raiz"))
            .and_then(|m| m.thread.as_ref())
            .map(|thread| thread.unread)
    }

    #[tokio::test]
    async fn mark_as_read_on_the_main_timeline_sends_a_main_receipt() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = room_with_thread(&server, &client).await;
        server
            .mock_send_receipt(ReceiptType::Read)
            .match_event_id(event_id!("$root"))
            .body_json(json!({ "thread_id": "main" }))
            .ok()
            .expect(1)
            .mount()
            .await;
        let handle =
            TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();
        wait_for(&handle, |s| !messages(s).is_empty()).await;

        handle.mark_as_read().await.unwrap();
    }

    #[tokio::test]
    async fn mark_as_read_on_a_thread_sends_a_thread_receipt() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = room_with_thread(&server, &client).await;
        server
            .mock_send_receipt(ReceiptType::Read)
            .match_event_id(event_id!("$r1"))
            .body_json(json!({ "thread_id": "$root" }))
            .ok()
            .expect(1)
            .mount()
            .await;
        let main =
            TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();
        let thread = main.open_thread("$root").await.unwrap();
        wait_for(&thread, |s| !messages(s).is_empty()).await;

        thread.mark_as_read().await.unwrap();
    }

    #[tokio::test]
    async fn watch_shows_unread_replies_and_refreshes_after_the_thread_is_read() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let own = client.user_id().unwrap().to_owned();
        let room = room_with_thread(&server, &client).await;
        let main =
            TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        main.watch(move |s| tx.send(s).is_ok());
        recv_until(&mut rx, |s| root_unread(s) == Some(1)).await;

        let _thread = main.open_thread("$root").await.unwrap();
        let f = EventFactory::new().room(room_id!("!a:b.c"));
        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id!("!a:b.c")).add_receipt(
                    f.read_receipts()
                        .add(
                            event_id!("$r1"),
                            &own,
                            EventReceiptType::Read,
                            ReceiptThread::Thread(event_id!("$root").to_owned()),
                        )
                        .into_event(),
                ),
            )
            .await;

        recv_until(&mut rx, |s| root_unread(s) == Some(0)).await;
    }

    #[tokio::test]
    async fn collapsing_the_thread_before_the_receipt_echo_still_refreshes_the_main_timeline() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let own = client.user_id().unwrap().to_owned();
        let room = room_with_thread(&server, &client).await;
        server
            .mock_send_receipt(ReceiptType::Read)
            .match_event_id(event_id!("$r1"))
            .body_json(json!({ "thread_id": "$root" }))
            .ok()
            .mount()
            .await;
        let main =
            TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
        main.watch(move |s| tx.send(s).is_ok());
        recv_until(&mut rx, |s| root_unread(s) == Some(1)).await;
        let thread = main.open_thread("$root").await.unwrap();
        wait_for(&thread, |s| !messages(s).is_empty()).await;

        thread.mark_as_read().await.unwrap();
        drop(thread);
        let f = EventFactory::new().room(room_id!("!a:b.c"));
        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id!("!a:b.c")).add_receipt(
                    f.read_receipts()
                        .add(
                            event_id!("$r1"),
                            &own,
                            EventReceiptType::Read,
                            ReceiptThread::Thread(event_id!("$root").to_owned()),
                        )
                        .into_event(),
                ),
            )
            .await;

        recv_until(&mut rx, |s| root_unread(s) == Some(0)).await;
    }

    #[tokio::test]
    async fn thread_timeline_watches_its_thread() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = room_with_thread(&server, &client).await;
        let main =
            TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        let thread = main.open_thread("$root").await.unwrap();

        assert_eq!(main.live_tasks(), 0);
        assert_eq!(thread.live_tasks(), 1);
    }

    #[tokio::test]
    async fn read_by_counts_receipts_on_later_events() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let own = client.user_id().unwrap().to_owned();
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("minha").sender(&own).event_id(event_id!("$1")))
                    .add_timeline_event(f.text_msg("resposta").sender(bob).event_id(event_id!("$2")))
                    .add_receipt(
                        f.read_receipts()
                            .add(event_id!("$2"), bob, EventReceiptType::Read, ReceiptThread::Unthreaded)
                            .into_event(),
                    ),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        let current = wait_for(&handle, |s| messages(s).len() >= 2).await;

        let mine = messages(&current).into_iter().find(|m| m.body.as_deref() == Some("minha")).unwrap();
        assert_eq!(mine.read_by, vec!["bob".to_owned()]);
    }

    fn reply_of<'a>(snapshot: &'a TimelineSnapshot, body: &str) -> Option<&'a ReplyPreview> {
        messages(snapshot)
            .into_iter()
            .find(|m| m.body.as_deref() == Some(body))
            .and_then(|m| m.reply_to.as_ref())
    }

    #[tokio::test]
    async fn reply_shows_the_original_already_in_the_timeline() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("original").sender(bob).event_id(event_id!("$1")))
                    .add_timeline_event(
                        f.text_msg("resposta").sender(bob).event_id(event_id!("$2")).reply_to(event_id!("$1")),
                    ),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();

        let current = wait_for(&handle, |s| reply_of(s, "resposta").is_some()).await;

        assert_eq!(
            reply_of(&current, "resposta"),
            Some(&ReplyPreview {
                state: ReplyState::Ready,
                sender_name: Some("bob".to_owned()),
                kind: Some(MessageKind::Text),
                body: Some("original".to_owned()),
            })
        );
        assert!(reply_of(&current, "original").is_none());
    }

    #[tokio::test]
    async fn watch_fetches_an_original_missing_from_the_timeline() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        server
            .mock_room_event()
            .match_event_id()
            .ok(f.text_msg("antiga").sender(bob).event_id(event_id!("$old")).into_event())
            .mount()
            .await;
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_timeline_event(
                    f.text_msg("resposta").sender(bob).event_id(event_id!("$2")).reply_to(event_id!("$old")),
                ),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();

        handle.watch(move |s| tx.send(s).is_ok());
        let mut last = TimelineSnapshot { items: Vec::new(), reached_start: false };
        while reply_of(&last, "resposta").map(|reply| reply.state) != Some(ReplyState::Ready) {
            last = tokio::time::timeout(Duration::from_secs(5), rx.recv()).await.unwrap().unwrap();
        }

        assert_eq!(reply_of(&last, "resposta").unwrap().body.as_deref(), Some("antiga"));
    }

    #[tokio::test]
    async fn watch_emits_now_and_on_new_events_and_drop_stops_it() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("um").sender(bob).event_id(event_id!("$1"))),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current()).await.unwrap();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();

        handle.watch(move |s| tx.send(s).is_ok());
        let mut last =
            tokio::time::timeout(Duration::from_secs(5), rx.recv()).await.unwrap().unwrap();
        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("dois").sender(bob).event_id(event_id!("$2"))),
            )
            .await;
        while !messages(&last).iter().any(|m| m.body.as_deref() == Some("dois")) {
            last = tokio::time::timeout(Duration::from_secs(5), rx.recv()).await.unwrap().unwrap();
        }

        assert_eq!(handle.live_tasks(), 1);
        drop(handle);
        assert!(tokio::time::timeout(Duration::from_secs(2), rx.recv()).await.unwrap().is_none());
    }
}
