use std::{
    collections::HashSet,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
};

use matrix_sdk::{
    deserialized_responses::RawAnySyncOrStrippedTimelineEvent,
    ruma::{MilliSecondsSinceUnixEpoch, OwnedEventId, OwnedRoomId, OwnedUserId},
    sync::Notification,
    Client, Room,
};

use crate::api::{notifications::RoomNotification, rooms::LatestMessageKind};
use crate::room_list::{message_kind, room_name, sender_name};

type Emit = Box<dyn FnMut(RoomNotification) -> bool + Send>;

struct Watch {
    since: MilliSecondsSinceUnixEpoch,
    known_invites: HashSet<OwnedRoomId>,
    delivered: HashSet<OwnedEventId>,
    emit: Emit,
}

// O SDK não remove handlers: registra um só e troca o destino a cada watch.
#[derive(Clone, Default)]
pub(crate) struct Notifier {
    current: Arc<Mutex<Option<Watch>>>,
    registered: Arc<AtomicBool>,
}

impl Notifier {
    pub(crate) async fn watch(
        &self,
        client: &Client,
        emit: impl FnMut(RoomNotification) -> bool + Send + 'static,
    ) {
        let known_invites = client
            .invited_rooms()
            .iter()
            .map(|room| room.room_id().to_owned())
            .collect();
        *self.current.lock().unwrap() = Some(Watch {
            since: MilliSecondsSinceUnixEpoch::now(),
            known_invites,
            delivered: HashSet::new(),
            emit: Box::new(emit),
        });
        if self.registered.swap(true, Ordering::SeqCst) {
            return;
        }
        let current = self.current.clone();
        client
            .register_notification_handler(move |notification: Notification, room: Room, _: Client| {
                let current = current.clone();
                async move { deliver(&current, &notification, &room).await }
            })
            .await;
    }
}

enum Candidate {
    Message {
        event_id: OwnedEventId,
        sender: OwnedUserId,
        timestamp: MilliSecondsSinceUnixEpoch,
        kind: LatestMessageKind,
        body: Option<String>,
    },
    Invite {
        sender: OwnedUserId,
    },
}

async fn deliver(current: &Mutex<Option<Watch>>, notification: &Notification, room: &Room) {
    let Some(candidate) = candidate(&notification.event, room) else {
        return;
    };
    if !accepts(current, &candidate, room) {
        return;
    }
    let item = build(candidate, room).await;
    let mut current = current.lock().unwrap();
    if let Some(watch) = current.as_mut() {
        if !(watch.emit)(item) {
            *current = None;
        }
    }
}

fn candidate(event: &RawAnySyncOrStrippedTimelineEvent, room: &Room) -> Option<Candidate> {
    match event {
        RawAnySyncOrStrippedTimelineEvent::Sync(raw) => {
            let event = raw.deserialize().ok()?;
            let (kind, body) = message_kind(&event);
            if kind == LatestMessageKind::Other {
                return None;
            }
            Some(Candidate::Message {
                event_id: event.event_id().to_owned(),
                sender: event.sender().to_owned(),
                timestamp: event.origin_server_ts(),
                kind,
                body,
            })
        }
        RawAnySyncOrStrippedTimelineEvent::Stripped(raw) => {
            let event_type = raw.get_field::<String>("type").ok()??;
            let state_key = raw.get_field::<String>("state_key").ok()??;
            let content = raw.get_field::<serde_json::Value>("content").ok()??;
            let is_own_invite = event_type == "m.room.member"
                && content.get("membership").and_then(|value| value.as_str()) == Some("invite")
                && state_key == room.own_user_id().as_str();
            if !is_own_invite {
                return None;
            }
            let sender = raw.get_field::<OwnedUserId>("sender").ok()??;
            Some(Candidate::Invite { sender })
        }
    }
}

// O SDK reavalia eventos reentregues (ex.: após reset do sliding sync): cada um passa uma vez.
// Convites stripped não têm origin_server_ts; o filtro deles é por sala já conhecida.
fn accepts(current: &Mutex<Option<Watch>>, candidate: &Candidate, room: &Room) -> bool {
    let mut current = current.lock().unwrap();
    let Some(watch) = current.as_mut() else {
        return false;
    };
    match candidate {
        Candidate::Message { event_id, timestamp, .. } => {
            *timestamp >= watch.since && watch.delivered.insert(event_id.clone())
        }
        Candidate::Invite { .. } => watch.known_invites.insert(room.room_id().to_owned()),
    }
}

async fn build(candidate: Candidate, room: &Room) -> RoomNotification {
    let (sender, kind, body, timestamp_ms, is_invite) = match candidate {
        Candidate::Message { sender, timestamp, kind, body, .. } => {
            (sender, kind, body, i64::from(timestamp.0), false)
        }
        Candidate::Invite { sender } => (
            sender,
            LatestMessageKind::Other,
            None,
            i64::from(MilliSecondsSinceUnixEpoch::now().0),
            true,
        ),
    };
    RoomNotification {
        room_id: room.room_id().to_string(),
        room_name: room_name(room).await,
        is_direct: room.is_dm(),
        is_invite,
        sender_name: sender_name(room, &sender).await,
        kind,
        body,
        timestamp_ms,
    }
}

#[cfg(test)]
mod tests {
    use matrix_sdk::{
        ruma::{
            events::room::member::MembershipState,
            push::{NewPushRule, NewSimplePushRule, Ruleset},
            event_id, room_id, user_id, MilliSecondsSinceUnixEpoch, RoomId,
        },
        test_utils::mocks::MatrixMockServer,
    };
    use matrix_sdk_test::{event_factory::EventFactory, InvitedRoomBuilder, JoinedRoomBuilder};
    use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver};

    use super::*;
    use crate::api::rooms::LatestMessageKind;

    fn now_plus(ms: u64) -> u64 {
        u64::from(MilliSecondsSinceUnixEpoch::now().0) + ms
    }

    // Sem o m.room.member próprio no store o SDK não avalia as regras de push.
    fn joined(client: &Client, room_id: &RoomId) -> JoinedRoomBuilder {
        let f = EventFactory::new().room(room_id);
        JoinedRoomBuilder::new(room_id)
            .add_state_event(f.member(client.user_id().unwrap()))
            .add_state_event(f.member(user_id!("@bob:b.c")).display_name("Bob"))
    }

    async fn watching(client: &Client, notifier: &Notifier) -> UnboundedReceiver<RoomNotification> {
        let (tx, rx) = unbounded_channel();
        notifier.watch(client, move |item| tx.send(item).is_ok()).await;
        rx
    }

    #[tokio::test]
    async fn message_from_someone_else_is_delivered() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        let notifier = Notifier::default();
        let mut rx = watching(&client, &notifier).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);

        server
            .sync_room(
                &client,
                joined(&client, room_id).add_timeline_event(
                    f.text_msg("oi").sender(user_id!("@bob:b.c")).server_ts(now_plus(1_000)),
                ),
            )
            .await;

        let item = rx.try_recv().expect("notificação entregue");
        assert_eq!(item.room_id, room_id.as_str());
        assert_eq!(item.sender_name, "Bob");
        assert_eq!(item.kind, LatestMessageKind::Text);
        assert_eq!(item.body.as_deref(), Some("oi"));
        assert!(!item.is_invite);
    }

    #[tokio::test]
    async fn own_and_old_messages_are_dropped() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        let notifier = Notifier::default();
        let mut rx = watching(&client, &notifier).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let me = client.user_id().unwrap().to_owned();

        server
            .sync_room(
                &client,
                joined(&client, room_id)
                    .add_timeline_event(f.text_msg("antiga").sender(user_id!("@bob:b.c")).server_ts(1_000))
                    .add_timeline_event(f.text_msg("minha").sender(&me).server_ts(now_plus(1_000)))
                    .add_timeline_event(
                        f.text_msg("nova").sender(user_id!("@bob:b.c")).server_ts(now_plus(2_000)),
                    ),
            )
            .await;

        assert_eq!(rx.try_recv().unwrap().body.as_deref(), Some("nova"));
        assert!(rx.try_recv().is_err());
    }

    #[tokio::test]
    async fn muted_room_is_dropped() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        let notifier = Notifier::default();
        let mut rx = watching(&client, &notifier).await;
        let room_id = room_id!("!m:b.c");
        let f = EventFactory::new().room(room_id);
        let mut rules = Ruleset::server_default(client.user_id().unwrap());
        rules
            .insert(NewPushRule::Room(NewSimplePushRule::new(room_id.to_owned(), vec![])), None, None)
            .unwrap();

        server
            .mock_sync()
            .ok_and_run(&client, |builder| {
                let other = room_id!("!a:b.c");
                builder
                    .add_global_account_data(f.push_rules(rules))
                    .add_joined_room(joined(&client, room_id).add_timeline_event(
                        f.text_msg("quieta").sender(user_id!("@bob:b.c")).server_ts(now_plus(1_000)),
                    ))
                    .add_joined_room(joined(&client, other).add_timeline_event(
                        EventFactory::new()
                            .room(other)
                            .text_msg("normal")
                            .sender(user_id!("@bob:b.c"))
                            .server_ts(now_plus(1_000)),
                    ));
            })
            .await;

        assert_eq!(rx.try_recv().unwrap().room_id, "!a:b.c");
        assert!(rx.try_recv().is_err());
    }

    #[tokio::test]
    async fn only_new_invites_are_delivered() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        let me = client.user_id().unwrap().to_owned();
        let invite = |room_id: &RoomId| {
            InvitedRoomBuilder::new(room_id).add_state_event(
                EventFactory::new()
                    .room(room_id)
                    .member(&me)
                    .membership(MembershipState::Invite)
                    .sender(user_id!("@bob:b.c")),
            )
        };
        server.sync_room(&client, invite(room_id!("!old:b.c"))).await;
        let notifier = Notifier::default();
        let mut rx = watching(&client, &notifier).await;

        server.sync_room(&client, invite(room_id!("!old:b.c"))).await;
        server.sync_room(&client, invite(room_id!("!new:b.c"))).await;

        let item = rx.try_recv().expect("convite novo entregue");
        assert_eq!(item.room_id, "!new:b.c");
        assert!(item.is_invite);
        assert_eq!(item.sender_name, "bob");
        assert!(rx.try_recv().is_err());
    }

    #[tokio::test]
    async fn second_watch_replaces_the_first() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        let notifier = Notifier::default();
        let mut first = watching(&client, &notifier).await;
        let mut second = watching(&client, &notifier).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);

        server
            .sync_room(
                &client,
                joined(&client, room_id).add_timeline_event(
                    f.text_msg("oi").sender(user_id!("@bob:b.c")).server_ts(now_plus(1_000)),
                ),
            )
            .await;

        assert!(second.try_recv().is_ok());
        assert!(first.try_recv().is_err());
    }

    #[tokio::test]
    async fn redelivered_message_notifies_once() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        let notifier = Notifier::default();
        let mut rx = watching(&client, &notifier).await;
        let room_id = room_id!("!a:b.c");
        let f = EventFactory::new().room(room_id);
        let event = || {
            f.text_msg("oi")
            .sender(user_id!("@bob:b.c"))
            .server_ts(now_plus(1_000))
            .event_id(event_id!("$same:b.c"))
        };

        server.sync_room(&client, joined(&client, room_id).add_timeline_event(event())).await;
        server.sync_room(&client, joined(&client, room_id).add_timeline_event(event())).await;

        assert!(rx.try_recv().is_ok());
        assert!(rx.try_recv().is_err());
    }

    #[tokio::test]
    async fn redelivered_invite_notifies_once() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        let me = client.user_id().unwrap().to_owned();
        let notifier = Notifier::default();
        let mut rx = watching(&client, &notifier).await;
        let invite = || {
            InvitedRoomBuilder::new(room_id!("!new:b.c")).add_state_event(
                EventFactory::new()
                    .room(room_id!("!new:b.c"))
                    .member(&me)
                    .membership(MembershipState::Invite)
                    .sender(user_id!("@bob:b.c")),
            )
        };

        server.sync_room(&client, invite()).await;
        server.sync_room(&client, invite()).await;

        assert!(rx.try_recv().is_ok());
        assert!(rx.try_recv().is_err());
    }
}
