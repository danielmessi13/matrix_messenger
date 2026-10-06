use std::{
    collections::{HashMap, HashSet},
    path::Path,
    sync::{Arc, Mutex},
    time::Duration,
};

use eyeball_im::Vector;
use futures_util::{pin_mut, stream, StreamExt};
use matrix_sdk::{
    attachment::AttachmentInfo,
    event_cache::PaginationStatus,
    ruma::{
        api::client::receipt::create_receipt::v3::ReceiptType,
        events::{
            room::message::{
                MessageType, RoomMessageEventContent, RoomMessageEventContentWithoutRelation,
            },
            StateEventContentChange,
        },
        EventId, OwnedEventId, OwnedUserId, UserId,
    },
    send_queue::SendHandle,
    Room,
};
use matrix_sdk_ui::timeline::{
    AnyOtherStateEventContentChange, AttachmentConfig, AttachmentSource, EventSendState,
    EventTimelineItem, MembershipChange, MsgLikeKind, Profile, Timeline, TimelineBuilder,
    TimelineDetails, TimelineFocus, TimelineItem, TimelineItemContent, TimelineReadReceiptTracking,
    TimelineUniqueId, VirtualTimelineItem,
};
use tokio::{runtime::Handle, task::AbortHandle};

use crate::{
    api::timeline::{
        ImageContent, MessageKind, ReplyPreview, ReplyState, RoomEvent, RoomEventKind, SendState,
        ThreadInfo, TimelineEntry, TimelineError, TimelineErrorKind, TimelineMessage,
        TimelineSnapshot,
    },
    diff_window::next_batch_or,
    media,
    threads::{changed_in, unread_by_thread, ThreadReads},
    typing,
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
            None => TimelineFocus::Live {
                hide_threaded_events: true,
            },
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
            let Ok((thread, _drop_handles)) =
                client.event_cache().thread(room.room_id(), &root).await
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
            // Na thread não há status; o stream encerrado pende para sempre.
            let (mut status, mut status_stream) = match timeline.live_back_pagination_status().await
            {
                Some((current, updates)) => (current, updates.chain(stream::pending()).boxed()),
                None => (
                    PaginationStatus::Idle {
                        hit_timeline_start: false,
                    },
                    stream::pending().boxed(),
                ),
            };
            let (mut items, stream) = timeline.subscribe().await;
            pin_mut!(stream);
            let mut fetched = HashSet::new();
            loop {
                let unread = match thread_root {
                    Some(_) => HashMap::new(),
                    None => unread_by_thread(&room).await,
                };
                fetch_missing_replies(&timeline, &items, &mut fetched);
                let paginating = matches!(status, PaginationStatus::Paginating);
                if !emit(snapshot(
                    &items,
                    &own_user,
                    thread_root.as_deref(),
                    &unread,
                    paginating,
                )) {
                    return;
                }
                let signal = async {
                    let reads = async {
                        match changed.as_mut() {
                            Some(changed) => changed_in(changed, room.room_id()).await,
                            None => std::future::pending().await,
                        }
                    };
                    let status_changed = async {
                        if let Some(next) = status_stream.next().await {
                            status = next;
                        }
                    };
                    tokio::select! {
                        () = reads => {}
                        () = status_changed => {}
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

    // Na timeline de thread o SDK mantém a resposta dentro da thread.
    pub(crate) async fn send_reply(
        &self,
        body: String,
        in_reply_to: &str,
    ) -> Result<(), TimelineError> {
        let event_id = OwnedEventId::try_from(in_reply_to).map_err(|error| {
            TimelineError::new(TimelineErrorKind::MessageNotFound, error.to_string())
        })?;
        self.timeline
            .send_reply(
                RoomMessageEventContentWithoutRelation::text_markdown(body),
                event_id,
            )
            .await?;
        Ok(())
    }

    // Pela fila de envio, como o texto: eco local na hora e o mesmo retry/cancel.
    pub(crate) async fn send_image(
        &self,
        path: &str,
        in_reply_to: Option<&str>,
    ) -> Result<(), TimelineError> {
        let invalid =
            |message: String| TimelineError::new(TimelineErrorKind::InvalidImage, message);
        let bytes = tokio::fs::read(path)
            .await
            .map_err(|error| invalid(error.to_string()))?;
        let filename = Path::new(path)
            .file_name()
            .and_then(|name| name.to_str())
            .ok_or_else(|| invalid(path.to_owned()))?
            .to_owned();
        let (mime, info) =
            media::image_attachment(&bytes).ok_or_else(|| invalid(filename.clone()))?;
        let in_reply_to = in_reply_to
            .map(|id| {
                OwnedEventId::try_from(id).map_err(|error| {
                    TimelineError::new(TimelineErrorKind::MessageNotFound, error.to_string())
                })
            })
            .transpose()?;
        let config = AttachmentConfig {
            info: Some(AttachmentInfo::Image(info)),
            in_reply_to,
            ..Default::default()
        };
        self.timeline
            .send_attachment(AttachmentSource::Data { bytes, filename }, mime, config)
            .use_send_queue()
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
                    Ok((thread, drop_handles)) => thread
                        .subscribe_to_thread_info()
                        .await
                        .ok()
                        .map(|info| (info, drop_handles)),
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

    pub(crate) fn watch_typing(&self, emit: impl FnMut(Vec<String>) -> bool + Send + 'static) {
        let task = self.runtime.spawn(typing::watch(self.room.clone(), emit));
        self.tasks.lock().unwrap().push(task.abort_handle());
    }

    pub(crate) async fn set_typing(&self, typing: bool) -> Result<(), TimelineError> {
        typing::set(&self.room, typing).await
    }

    pub(crate) async fn open_thread(&self, root_event_id: &str) -> Result<Self, TimelineError> {
        let root = OwnedEventId::try_from(root_event_id).map_err(|error| {
            TimelineError::new(TimelineErrorKind::MessageNotFound, error.to_string())
        })?;
        Self::open(
            self.room.clone(),
            Some(root),
            self.reads.clone(),
            self.runtime.clone(),
        )
        .await
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
        self.tasks
            .lock()
            .unwrap()
            .iter()
            .filter(|task| !task.is_finished())
            .count()
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
        TimelineDetails::Ready(Profile {
            display_name: Some(name),
            ..
        }) if !name.is_empty() => name.clone(),
        _ => sender.localpart().to_owned(),
    }
}

pub(crate) fn kind_and_body(
    content: &TimelineItemContent,
) -> Option<(MessageKind, Option<String>)> {
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

fn image(content: &TimelineItemContent) -> Option<ImageContent> {
    match content.as_message()?.msgtype() {
        MessageType::Image(image) => Some(media::image_content(image)),
        _ => None,
    }
}

fn send_state(item: &EventTimelineItem) -> SendState {
    match item.send_state() {
        None | Some(EventSendState::Sent { .. }) => SendState::Sent,
        Some(EventSendState::NotSentYet { .. }) => SendState::Sending,
        Some(EventSendState::SendingFailed {
            is_recoverable: true,
            ..
        }) => SendState::Failed,
        Some(EventSendState::SendingFailed {
            is_recoverable: false,
            ..
        }) => SendState::Rejected,
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
        if !matches!(reply.event, TimelineDetails::Unavailable)
            || !fetched.insert(event_id.to_owned())
        {
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

fn reply_preview(item: &EventTimelineItem, own_user: &UserId) -> Option<ReplyPreview> {
    let reply = item.content().in_reply_to()?;
    let event_id = reply.event_id.to_string();
    Some(match &reply.event {
        TimelineDetails::Ready(event) => {
            let (kind, body) = kind_and_body(&event.content).unwrap_or((MessageKind::Other, None));
            ReplyPreview {
                event_id,
                state: ReplyState::Ready,
                is_own: event.sender.as_str() == own_user.as_str(),
                sender_name: Some(profile_name(&event.sender, &event.sender_profile)),
                kind: Some(kind),
                body,
            }
        }
        TimelineDetails::Error(_) => ReplyPreview {
            event_id,
            state: ReplyState::Unavailable,
            is_own: false,
            sender_name: None,
            kind: None,
            body: None,
        },
        TimelineDetails::Unavailable | TimelineDetails::Pending => ReplyPreview {
            event_id,
            state: ReplyState::Loading,
            is_own: false,
            sender_name: None,
            kind: None,
            body: None,
        },
    })
}

fn thread_info(
    item: &EventTimelineItem,
    unread: &HashMap<OwnedEventId, u32>,
) -> Option<ThreadInfo> {
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
        unread: item
            .event_id()
            .and_then(|id| unread.get(id))
            .copied()
            .unwrap_or(0),
    })
}

// O unique_id passa do eco local para o evento confirmado; o event_id e o transaction_id não.
fn message(
    id: &TimelineUniqueId,
    item: &EventTimelineItem,
    own_user: &UserId,
    unread: &HashMap<OwnedEventId, u32>,
) -> Option<TimelineMessage> {
    let (kind, body) = kind_and_body(item.content())?;
    Some(TimelineMessage {
        id: id.0.clone(),
        event_id: item.event_id().map(ToString::to_string),
        sender_id: item.sender().to_string(),
        sender_name: profile_name(item.sender(), item.sender_profile()),
        is_own: item.is_own(),
        timestamp_ms: i64::from(item.timestamp().0),
        kind,
        body,
        edited: item
            .content()
            .as_message()
            .is_some_and(|message| message.is_edited()),
        send_state: send_state(item),
        can_reply: item.can_be_replied_to(),
        thread: thread_info(item, unread),
        reply_to: reply_preview(item, own_user),
        read_by: Vec::new(),
        image: image(item.content()),
    })
}

fn non_empty(text: &str) -> Option<String> {
    (!text.is_empty()).then(|| text.to_owned())
}

fn room_event(
    id: &TimelineUniqueId,
    item: &EventTimelineItem,
    own_user: &UserId,
) -> Option<RoomEvent> {
    let mut target_name = None;
    let mut target_is_own = false;
    let mut value = None;
    let kind = match item.content() {
        TimelineItemContent::MembershipChange(change) => {
            let kind = match change.change()? {
                MembershipChange::Joined | MembershipChange::InvitationAccepted => {
                    RoomEventKind::Joined
                }
                MembershipChange::Left => RoomEventKind::Left,
                MembershipChange::Invited => RoomEventKind::Invited,
                MembershipChange::InvitationRejected => RoomEventKind::InviteDeclined,
                MembershipChange::Kicked => RoomEventKind::Kicked,
                MembershipChange::Banned | MembershipChange::KickedAndBanned => {
                    RoomEventKind::Banned
                }
                MembershipChange::Unbanned => RoomEventKind::Unbanned,
                _ => return None,
            };
            let user = change.user_id();
            if user != item.sender() {
                target_name = Some(
                    change
                        .display_name()
                        .filter(|name| !name.is_empty())
                        .unwrap_or_else(|| user.localpart().to_owned()),
                );
                target_is_own = user == own_user;
            }
            kind
        }
        TimelineItemContent::ProfileChange(profile) => {
            let change = profile.displayname_change()?;
            target_name = change.old.as_deref().and_then(non_empty);
            value = change.new.as_deref().and_then(non_empty);
            RoomEventKind::DisplayNameChanged
        }
        TimelineItemContent::OtherState(state) => match state.content() {
            AnyOtherStateEventContentChange::RoomCreate(_) => RoomEventKind::Created,
            AnyOtherStateEventContentChange::RoomName(change) => {
                if let StateEventContentChange::Original { content, .. } = change {
                    value = non_empty(&content.name);
                }
                RoomEventKind::NameChanged
            }
            AnyOtherStateEventContentChange::RoomTopic(change) => {
                if let StateEventContentChange::Original { content, .. } = change {
                    value = non_empty(&content.topic);
                }
                RoomEventKind::TopicChanged
            }
            AnyOtherStateEventContentChange::RoomAvatar(_) => RoomEventKind::AvatarChanged,
            AnyOtherStateEventContentChange::RoomEncryption(_) => RoomEventKind::EncryptionEnabled,
            _ => return None,
        },
        _ => return None,
    };
    Some(RoomEvent {
        id: id.0.clone(),
        sender_name: profile_name(item.sender(), item.sender_profile()),
        is_own: item.is_own(),
        timestamp_ms: i64::from(item.timestamp().0),
        kind,
        target_name,
        target_is_own,
        value,
    })
}

// Ao chegar ao início, a timeline de thread inclui a raiz, que já aparece na conversa principal.
pub(crate) fn snapshot(
    items: &Vector<Arc<TimelineItem>>,
    own_user: &UserId,
    thread_root: Option<&EventId>,
    unread: &HashMap<OwnedEventId, u32>,
    paginating: bool,
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
            let message = message(item.unique_id(), event, own_user, unread);
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
                if thread_root.is_none() {
                    if let Some(room_event) = room_event(item.unique_id(), event, own_user) {
                        entries.push(TimelineEntry {
                            date_divider_ms: None,
                            message: None,
                            room_event: Some(room_event),
                        });
                    }
                }
                continue;
            };
            entries.push(TimelineEntry {
                date_divider_ms: None,
                message: Some(message),
                room_event: None,
            });
        } else if let Some(virtual_item) = item.as_virtual() {
            match virtual_item {
                VirtualTimelineItem::DateDivider(day) => {
                    drop_trailing_divider(&mut entries);
                    entries.push(TimelineEntry {
                        date_divider_ms: Some(i64::from(day.0)),
                        message: None,
                        room_event: None,
                    });
                }
                VirtualTimelineItem::TimelineStart => reached_start = true,
                VirtualTimelineItem::ReadMarker => {}
            }
        }
    }
    drop_trailing_divider(&mut entries);
    if let Some((index, readers)) = last_read {
        if let Some(message) = entries[index].message.as_mut() {
            message.read_by = readers
                .iter()
                .map(|user| {
                    names
                        .get(user)
                        .cloned()
                        .unwrap_or_else(|| user.localpart().to_owned())
                })
                .collect();
        }
    }
    TimelineSnapshot {
        items: entries,
        reached_start,
        paginating,
    }
}

// O SDK põe divisor de dia também antes de eventos que não mostramos; sozinho, ele impede o estado vazio.
fn drop_trailing_divider(entries: &mut Vec<TimelineEntry>) {
    if entries
        .last()
        .is_some_and(|entry| entry.date_divider_ms.is_some())
    {
        entries.pop();
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use matrix_sdk::ruma::{events::AnyTimelineEvent, serde::Raw, EventId};
    use matrix_sdk::{
        ruma::{
            api::client::receipt::create_receipt::v3::ReceiptType,
            event_id,
            events::receipt::{ReceiptThread, ReceiptType as EventReceiptType},
            mxc_uri, room_id, user_id, UInt,
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
        snapshot
            .items
            .iter()
            .filter_map(|entry| entry.message.as_ref())
            .collect()
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
                false,
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
                &HashMap::new(),
                false
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
                            .add(
                                event_id!("$3"),
                                bob,
                                EventReceiptType::Read,
                                ReceiptThread::Unthreaded,
                            )
                            .into_event(),
                    ),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        let current = wait_for(&handle, |s| messages(s).len() >= 4).await;

        let all = messages(&current);
        assert!(all.iter().all(|m| m.body.as_deref() != Some("resposta")));
        let first = all
            .iter()
            .find(|m| m.body.as_deref() == Some("**oi**"))
            .unwrap();
        assert_eq!(
            (first.kind, first.body.as_deref()),
            (MessageKind::Text, Some("**oi**"))
        );
        assert_eq!(first.sender_name, "bob");
        assert!(!first.is_own);
        assert_eq!(
            all.iter()
                .find(|m| m.body.as_deref() == Some("aviso"))
                .unwrap()
                .kind,
            MessageKind::Notice
        );
        let root = all
            .iter()
            .find(|m| m.body.as_deref() == Some("raiz"))
            .unwrap();
        let thread = root.thread.as_ref().expect("resumo da thread");
        assert_eq!(
            (thread.root_event_id.as_str(), thread.replies),
            ("$root", 1)
        );
        let mine = all
            .iter()
            .find(|m| m.body.as_deref() == Some("minha"))
            .unwrap();
        assert!(mine.is_own);
        assert_eq!(mine.read_by, vec!["bob".to_owned()]);
        assert!(all
            .iter()
            .filter(|m| m.body.as_deref() != Some("minha"))
            .all(|m| m.read_by.is_empty()));
        assert!(current
            .items
            .iter()
            .any(|entry| entry.date_divider_ms.is_some()));
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
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

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
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

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
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        handle
            .send_markdown("**negrito**".to_owned())
            .await
            .unwrap();
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
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
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
            if items
                .iter()
                .filter_map(|item| item.as_event())
                .any(|event| !event.is_local_echo())
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
        let remote = wait_for(&handle, |s| messages(s).len() == 1).await;

        let items = handle.timeline.items().await;
        assert!(items
            .iter()
            .filter_map(|item| item.as_event())
            .all(|event| !event.is_local_echo()));
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
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        handle.send_markdown("oi".to_owned()).await.unwrap();
        let current = wait_for(&handle, |s| {
            messages(s)
                .iter()
                .any(|m| m.send_state == SendState::Rejected)
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
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        handle.send_markdown("oi".to_owned()).await.unwrap();
        let current = wait_for(&handle, |s| {
            messages(s)
                .iter()
                .any(|m| m.send_state == SendState::Failed)
        })
        .await;
        drop(failing);
        server.mock_room_send().ok(event_id!("$sent")).mount().await;
        handle.retry(&messages(&current)[0].id).await.unwrap();

        wait_for(&handle, |s| {
            messages(s).iter().any(|m| m.send_state == SendState::Sent)
        })
        .await;
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
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        handle.send_markdown("um".to_owned()).await.unwrap();
        let current = wait_for(&handle, |s| {
            messages(s)
                .iter()
                .any(|m| m.send_state == SendState::Rejected)
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
                JoinedRoomBuilder::new(room_id).add_timeline_event(
                    f.text_msg("raiz").sender(bob).event_id(event_id!("$root")),
                ),
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
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

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
        mut ready: impl FnMut(&TimelineSnapshot) -> bool,
    ) -> TimelineSnapshot {
        loop {
            let current = tokio::time::timeout(Duration::from_secs(5), rx.recv())
                .await
                .unwrap()
                .unwrap();
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
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
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
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
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
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
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
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
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
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

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
                    .add_timeline_event(
                        f.text_msg("resposta").sender(bob).event_id(event_id!("$2")),
                    )
                    .add_receipt(
                        f.read_receipts()
                            .add(
                                event_id!("$2"),
                                bob,
                                EventReceiptType::Read,
                                ReceiptThread::Unthreaded,
                            )
                            .into_event(),
                    ),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        let current = wait_for(&handle, |s| messages(s).len() >= 2).await;

        let mine = messages(&current)
            .into_iter()
            .find(|m| m.body.as_deref() == Some("minha"))
            .unwrap();
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
                    .add_timeline_event(
                        f.text_msg("original").sender(bob).event_id(event_id!("$1")),
                    )
                    .add_timeline_event(
                        f.text_msg("resposta")
                            .sender(bob)
                            .event_id(event_id!("$2"))
                            .reply_to(event_id!("$1")),
                    ),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        let current = wait_for(&handle, |s| reply_of(s, "resposta").is_some()).await;

        assert_eq!(
            reply_of(&current, "resposta"),
            Some(&ReplyPreview {
                event_id: "$1".to_owned(),
                state: ReplyState::Ready,
                is_own: false,
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
            .ok(f
                .text_msg("antiga")
                .sender(bob)
                .event_id(event_id!("$old"))
                .into_event())
            .mount()
            .await;
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_timeline_event(
                    f.text_msg("resposta")
                        .sender(bob)
                        .event_id(event_id!("$2"))
                        .reply_to(event_id!("$old")),
                ),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();

        handle.watch(move |s| tx.send(s).is_ok());
        let mut last = TimelineSnapshot {
            items: Vec::new(),
            reached_start: false,
            paginating: false,
        };
        while reply_of(&last, "resposta").map(|reply| reply.state) != Some(ReplyState::Ready) {
            last = tokio::time::timeout(Duration::from_secs(5), rx.recv())
                .await
                .unwrap()
                .unwrap();
        }

        assert_eq!(
            reply_of(&last, "resposta").unwrap().body.as_deref(),
            Some("antiga")
        );
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
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();

        handle.watch(move |s| tx.send(s).is_ok());
        let mut last = tokio::time::timeout(Duration::from_secs(5), rx.recv())
            .await
            .unwrap()
            .unwrap();
        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("dois").sender(bob).event_id(event_id!("$2"))),
            )
            .await;
        while !messages(&last)
            .iter()
            .any(|m| m.body.as_deref() == Some("dois"))
        {
            last = tokio::time::timeout(Duration::from_secs(5), rx.recv())
                .await
                .unwrap()
                .unwrap();
        }

        assert_eq!(handle.live_tasks(), 1);
        drop(handle);
        assert!(tokio::time::timeout(Duration::from_secs(2), rx.recv())
            .await
            .unwrap()
            .is_none());
    }

    async fn sent_relation(server: &MatrixMockServer) -> serde_json::Value {
        for _ in 0..250 {
            let requests = server
                .server()
                .received_requests()
                .await
                .unwrap_or_default();
            let sent = requests.iter().rev().find(|request| {
                request.method.as_str() == "PUT" && request.url.path().contains("/send/")
            });
            if let Some(request) = sent {
                let body: serde_json::Value = serde_json::from_slice(&request.body).unwrap();
                return body["m.relates_to"].clone();
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        panic!("nenhum envio");
    }

    #[tokio::test]
    async fn send_reply_in_main_quotes_without_thread() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_timeline_event(
                    f.text_msg("um")
                        .sender(user_id!("@bob:b.c"))
                        .event_id(event_id!("$1")),
                ),
            )
            .await;
        server.mock_room_state_encryption().plain().mount().await;
        server.mock_room_send().ok(event_id!("$sent")).mount().await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        handle.send_reply("re".to_owned(), "$1").await.unwrap();

        let relation = sent_relation(&server).await;
        assert_eq!(relation["m.in_reply_to"]["event_id"], "$1");
        assert!(relation.get("rel_type").is_none());
    }

    #[tokio::test]
    async fn send_in_empty_thread_starts_it() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_timeline_event(
                    f.text_msg("raiz")
                        .sender(user_id!("@bob:b.c"))
                        .event_id(event_id!("$root")),
                ),
            )
            .await;
        server
            .mock_room_relations()
            .match_target_event(event_id!("$root").to_owned())
            .ok(RoomRelationsResponseTemplate::default())
            .mount()
            .await;
        server.mock_room_state_encryption().plain().mount().await;
        server.mock_room_send().ok(event_id!("$sent")).mount().await;
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
        let thread = main.open_thread("$root").await.unwrap();

        thread.send_markdown("oi".to_owned()).await.unwrap();

        let relation = sent_relation(&server).await;
        assert_eq!(relation["rel_type"], "m.thread");
        assert_eq!(relation["event_id"], "$root");
    }

    #[tokio::test]
    async fn send_reply_in_thread_stays_in_thread() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = room_with_thread(&server, &client).await;
        server.mock_room_state_encryption().plain().mount().await;
        server.mock_room_send().ok(event_id!("$sent")).mount().await;
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
        let thread = main.open_thread("$root").await.unwrap();

        thread.send_reply("re".to_owned(), "$r1").await.unwrap();

        let relation = sent_relation(&server).await;
        assert_eq!(relation["rel_type"], "m.thread");
        assert_eq!(relation["event_id"], "$root");
        assert_eq!(relation["m.in_reply_to"]["event_id"], "$r1");
        // O SDK omite o campo quando é falso.
        assert!(relation
            .get("is_falling_back")
            .is_none_or(|value| value == false));
        let current = wait_for(&thread, |s| messages(s).iter().any(|m| m.is_own)).await;
        let mine = messages(&current).into_iter().find(|m| m.is_own).unwrap();
        assert_eq!(
            mine.reply_to.as_ref().map(|reply| reply.event_id.as_str()),
            Some("$r1")
        );
    }

    #[tokio::test]
    async fn send_reply_with_invalid_id_is_message_not_found() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        let error = handle
            .send_reply("re".to_owned(), "não é id")
            .await
            .unwrap_err();

        assert_eq!(error.kind, TimelineErrorKind::MessageNotFound);
    }

    #[tokio::test]
    async fn reply_preview_carries_the_event_id_and_whether_it_is_mine() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let own = client.user_id().unwrap().to_owned();
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("minha").sender(&own).event_id(event_id!("$m")))
                    .add_timeline_event(
                        f.text_msg("re")
                            .sender(user_id!("@bob:b.c"))
                            .event_id(event_id!("$re"))
                            .reply_to(event_id!("$m")),
                    ),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        let current = wait_for(&handle, |s| {
            reply_of(s, "re").is_some_and(|reply| reply.state == ReplyState::Ready)
        })
        .await;

        let reply = reply_of(&current, "re").unwrap();
        assert_eq!((reply.event_id.as_str(), reply.is_own), ("$m", true));
        let answer = messages(&current)
            .into_iter()
            .find(|m| m.body.as_deref() == Some("re"))
            .unwrap();
        assert_eq!(answer.event_id.as_deref(), Some("$re"));
        assert!(answer.can_reply);
    }

    #[tokio::test]
    async fn local_echo_has_no_event_id_and_cannot_be_replied() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        server.mock_room_state_encryption().plain().mount().await;
        server.mock_room_send().error500().mount().await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        handle.send_markdown("oi".to_owned()).await.unwrap();
        let current = wait_for(&handle, |s| messages(s).len() == 1).await;

        let echo = messages(&current)[0];
        assert_eq!(echo.event_id, None);
        assert!(!echo.can_reply);
    }

    fn hidden_events(f: &EventFactory, count: usize) -> Vec<Raw<AnyTimelineEvent>> {
        (0..count)
            .map(|_| {
                f.default_power_levels()
                    .sender(user_id!("@bob:b.c"))
                    .into_raw_timeline()
            })
            .collect()
    }

    fn watched(handle: &TimelineHandle) -> tokio::sync::mpsc::UnboundedReceiver<TimelineSnapshot> {
        let (tx, rx) = tokio::sync::mpsc::unbounded_channel();
        handle.watch(move |snapshot| tx.send(snapshot).is_ok());
        rx
    }

    fn text_page(f: &EventFactory, prefix: &str, count: usize) -> Vec<Raw<AnyTimelineEvent>> {
        (0..count)
            .map(|i| {
                f.text_msg(format!("{prefix}{i}"))
                    .sender(user_id!("@bob:b.c"))
                    .event_id(&EventId::parse(format!("${prefix}{i}")).unwrap())
                    .into_raw_timeline()
            })
            .collect()
    }

    async fn limited_room(server: &MatrixMockServer, client: &matrix_sdk::Client) -> Room {
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        server
            .sync_room(
                client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(
                        f.text_msg("última")
                            .sender(user_id!("@bob:b.c"))
                            .event_id(event_id!("$last")),
                    )
                    .set_timeline_limited()
                    .set_timeline_prev_batch("p0"),
            )
            .await
    }

    #[tokio::test]
    async fn thread_timeline_stays_idle() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = room_with_thread(&server, &client).await;
        let main = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
        let thread = main.open_thread("$root").await.unwrap();
        let f = EventFactory::new().room(room_id!("!a:b.c"));
        // Montado depois de abrir: a busca da abertura falha e a página fica para o paginate_backwards.
        server
            .mock_room_relations()
            .match_target_event(event_id!("$root").to_owned())
            .ok(RoomRelationsResponseTemplate::default().events(vec![f
                .text_msg("antiga")
                .sender(user_id!("@bob:b.c"))
                .event_id(event_id!("$r0"))
                .in_thread(event_id!("$root"), event_id!("$root"))
                .into_raw_timeline()]))
            .expect(1)
            .mount()
            .await;
        let mut rx = watched(&thread);
        let mut seen = vec![recv_until(&mut rx, |_| true).await.paginating];

        thread.paginate_backwards().await.unwrap();

        recv_until(&mut rx, |s| {
            seen.push(s.paginating);
            messages(s)
                .iter()
                .any(|m| m.body.as_deref() == Some("antiga"))
        })
        .await;
        while let Ok(Some(s)) = tokio::time::timeout(Duration::from_millis(200), rx.recv()).await {
            seen.push(s.paginating);
        }
        assert!(seen.iter().all(|paginating| !paginating), "{seen:?}");
    }

    #[tokio::test]
    async fn snapshot_reports_paginating_while_the_server_answers() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = limited_room(&server, &client).await;
        let f = EventFactory::new().room(room.room_id());
        server
            .mock_room_messages()
            .match_from("p0")
            .ok(RoomMessagesResponseTemplate::default()
                .events(text_page(&f, "a", 5))
                .end_token("p1")
                .with_delay(Duration::from_millis(300)))
            .mount()
            .await;
        let handle = Arc::new(
            TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
                .await
                .unwrap(),
        );
        let mut rx = watched(&handle);
        assert!(!recv_until(&mut rx, |_| true).await.paginating);

        let paginating = {
            let handle = handle.clone();
            tokio::spawn(async move { handle.paginate_backwards().await })
        };

        recv_until(&mut rx, |s| s.paginating).await;
        recv_until(&mut rx, |s| !s.paginating).await;
        assert!(paginating.await.unwrap().is_ok());
    }

    #[tokio::test]
    async fn page_with_only_hidden_events_ends_idle_without_reaching_start() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = limited_room(&server, &client).await;
        let f = EventFactory::new().room(room.room_id());
        server
            .mock_room_messages()
            .match_from("p0")
            .ok(RoomMessagesResponseTemplate::default()
                .events(hidden_events(&f, 5))
                .end_token("p1"))
            .mount()
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
        let mut rx = watched(&handle);

        let reached = handle.paginate_backwards().await.unwrap();

        assert!(!reached);
        let mut last = recv_until(&mut rx, |_| true).await;
        while let Ok(Some(s)) = tokio::time::timeout(Duration::from_millis(300), rx.recv()).await {
            last = s;
        }
        assert!(!last.paginating);
        assert!(!last.reached_start);
    }

    #[tokio::test]
    async fn snapshot_drops_the_divider_of_a_day_without_messages() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        let day = 86_400_000_u64;
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.default_power_levels().sender(bob).server_ts(day))
                    .add_timeline_event(f.text_msg("oi").sender(bob).server_ts(3 * day)),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        let current = wait_for(&handle, |s| !messages(s).is_empty()).await;

        let dividers: Vec<_> = current
            .items
            .iter()
            .filter_map(|entry| entry.date_divider_ms)
            .collect();
        assert_eq!(dividers.len(), 1);
        assert!(current.items[0].date_divider_ms.is_some());
        assert!(current.items[1].message.is_some());
    }

    fn room_events(snapshot: &TimelineSnapshot) -> Vec<&RoomEvent> {
        snapshot
            .items
            .iter()
            .filter_map(|entry| entry.room_event.as_ref())
            .collect()
    }

    #[tokio::test]
    async fn snapshot_shows_room_events_in_order() {
        use matrix_sdk::ruma::{events::room::member::MembershipState, RoomVersionId};
        use matrix_sdk_test::event_factory::PreviousMembership;

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
                    .add_timeline_event(f.create(&own, RoomVersionId::V11))
                    .add_timeline_event(f.member(&own))
                    .add_timeline_event(f.default_power_levels().sender(&own))
                    .add_timeline_event(f.member(bob).sender(&own).invited(bob).display_name("Bob"))
                    .add_timeline_event(
                        f.member(bob)
                            .display_name("Bob")
                            .previous(MembershipState::Invite),
                    )
                    .add_timeline_event(f.room_name("Sala").sender(&own))
                    .add_timeline_event(f.room_topic("").sender(bob))
                    .add_timeline_event(f.room_encryption().sender(&own))
                    .add_timeline_event(f.member(bob).display_name("Roberto").previous(
                        PreviousMembership::new(MembershipState::Join).display_name("Bob"),
                    )),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        let current = wait_for(&handle, |s| room_events(s).len() >= 8).await;

        let events: Vec<_> = room_events(&current)
            .iter()
            .map(|e| {
                (
                    e.kind,
                    e.is_own,
                    e.target_name.as_deref(),
                    e.target_is_own,
                    e.value.as_deref(),
                )
            })
            .collect();
        assert_eq!(
            events,
            vec![
                (RoomEventKind::Created, true, None, false, None),
                (RoomEventKind::Joined, true, None, false, None),
                (RoomEventKind::Invited, true, Some("Bob"), false, None),
                (RoomEventKind::Joined, false, None, false, None),
                (RoomEventKind::NameChanged, true, None, false, Some("Sala")),
                (RoomEventKind::TopicChanged, false, None, false, None),
                (RoomEventKind::EncryptionEnabled, true, None, false, None),
                (
                    RoomEventKind::DisplayNameChanged,
                    false,
                    Some("Bob"),
                    false,
                    Some("Roberto")
                ),
            ]
        );
        assert!(room_events(&current)
            .iter()
            .filter(|e| !e.is_own)
            .all(|e| e.sender_name == "Roberto"));
    }

    #[tokio::test]
    async fn snapshot_carries_the_image_of_an_image_message() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(
                        f.image("foto.png".to_owned(), mxc_uri!("mxc://b.c/foto").to_owned())
                            .sender(user_id!("@bob:b.c")),
                    )
                    .add_timeline_event(f.text_msg("oi").sender(user_id!("@bob:b.c"))),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        let current = wait_for(&handle, |s| messages(s).len() == 2).await;

        let all = messages(&current);
        assert_eq!(
            (all[0].kind, all[0].body.as_deref()),
            (MessageKind::Image, None)
        );
        let image = all[0].image.as_ref().expect("conteúdo da imagem");
        assert_eq!(image.filename, "foto.png");
        assert!(image.media.contains("mxc://b.c/foto"));
        assert!(all[1].image.is_none());
    }

    #[tokio::test]
    async fn send_image_shows_a_local_echo_whose_bytes_load_from_the_cache() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        server.mock_room_state_encryption().plain().mount().await;
        server
            .mock_authenticated_media_config()
            .ok(UInt::from(1_000_000_u32))
            .mount()
            .await;
        server
            .mock_media_config()
            .ok(UInt::from(1_000_000_u32))
            .mount()
            .await;
        // Upload pendente: o eco fica local enquanto o teste o confere.
        server
            .mock_upload()
            .respond_with(wiremock::ResponseTemplate::new(200).set_delay(Duration::from_secs(60)))
            .mount()
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
        let path = std::path::Path::new(&crate::test_support::temp_data_dir("send_image"))
            .join("gato.png");
        let bytes = crate::test_support::png(40, 30);
        std::fs::write(&path, &bytes).unwrap();

        handle
            .send_image(path.to_str().unwrap(), None)
            .await
            .unwrap();
        let current = wait_for(&handle, |s| messages(s).len() == 1).await;

        let echo = messages(&current)[0];
        assert!(echo.is_own);
        assert_eq!(
            (echo.kind, echo.send_state),
            (MessageKind::Image, SendState::Sending)
        );
        let image = echo.image.as_ref().unwrap();
        assert_eq!(image.filename, "gato.png");
        assert_eq!((image.width, image.height), (Some(40), Some(30)));
        assert_eq!(image.mimetype.as_deref(), Some("image/png"));
        let loaded = media::load(&client, &image.media, true).await.unwrap();
        assert_eq!(loaded, bytes);
    }

    #[tokio::test]
    async fn send_image_rejects_a_file_that_is_not_an_image() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room = server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
        let dir = crate::test_support::temp_data_dir("send_not_image");
        let path = std::path::Path::new(&dir).join("nota.png");
        std::fs::write(&path, b"texto com extensao de imagem").unwrap();

        for target in [path.to_str().unwrap(), "/nao/existe.png"] {
            let error = handle.send_image(target, None).await.unwrap_err();
            assert_eq!(error.kind, TimelineErrorKind::InvalidImage, "{target}");
        }
    }

    #[tokio::test]
    async fn day_with_only_ignored_room_events_has_no_divider() {
        let server = MatrixMockServer::new().await;
        let client = client(&server).await;
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let f = EventFactory::new().room(room_id);
        let day = 86_400_000_u64;
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.default_power_levels().sender(bob).server_ts(day))
                    .add_timeline_event(f.room_name("Sala").sender(bob).server_ts(3 * day)),
            )
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        let current = wait_for(&handle, |s| !room_events(s).is_empty()).await;

        assert_eq!(current.items.len(), 2, "{current:#?}");
        assert!(current.items[0].date_divider_ms.is_some());
        assert_eq!(
            current.items[1].room_event.as_ref().map(|e| e.kind),
            Some(RoomEventKind::NameChanged)
        );
    }
}
