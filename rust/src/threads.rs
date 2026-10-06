use std::collections::{HashMap, HashSet};

use matrix_sdk::{
    ruma::{OwnedEventId, OwnedRoomId, RoomId},
    serde_helpers::extract_thread_root,
    Room, ThreadingSupport,
};
use tokio::sync::broadcast::{self, error::RecvError};

// Com threads ligadas a sala deixa de contar respostas de thread, e cada thread ganha a própria contagem.
pub(crate) const THREADING: ThreadingSupport =
    ThreadingSupport::Enabled { with_subscriptions: false };

const CAPACITY: usize = 64;

// Ler uma thread não muda o RoomInfo; este aviso faz a lista e a conversa recalcularem.
#[derive(Clone)]
pub(crate) struct ThreadReads(broadcast::Sender<OwnedRoomId>);

impl Default for ThreadReads {
    fn default() -> Self {
        Self(broadcast::channel(CAPACITY).0)
    }
}

impl ThreadReads {
    pub(crate) fn notify(&self, room_id: &RoomId) {
        let _ = self.0.send(room_id.to_owned());
    }

    pub(crate) fn subscribe(&self) -> broadcast::Receiver<OwnedRoomId> {
        self.0.subscribe()
    }
}

pub(crate) async fn changed_in(receiver: &mut broadcast::Receiver<OwnedRoomId>, room_id: &RoomId) {
    loop {
        match receiver.recv().await {
            Ok(changed) if changed.as_str() != room_id.as_str() => continue,
            Ok(_) | Err(RecvError::Lagged(_)) | Err(RecvError::Closed) => return,
        }
    }
}

// O SDK não lista as threads da sala; as raízes saem dos eventos em memória.
pub(crate) async fn unread_by_thread(room: &Room) -> HashMap<OwnedEventId, u32> {
    let Ok((cache, _drop_handles)) = room.event_cache().await else {
        return HashMap::new();
    };
    let Ok(events) = cache.events().await else {
        return HashMap::new();
    };
    let mut roots = HashSet::new();
    for event in &events {
        if event.thread_summary.summary().is_some() {
            if let Some(id) = event.event_id() {
                roots.insert(id.to_owned());
            }
        }
        if let Some(root) = extract_thread_root(event.raw()) {
            roots.insert(root);
        }
    }
    let client = room.client();
    let event_cache = client.event_cache();
    let mut unread = HashMap::new();
    for root in roots {
        let Ok((thread, _drop_handles)) = event_cache.thread(room.room_id(), &root).await else {
            continue;
        };
        let count = thread.num_unread_messages().await.unwrap_or(0);
        if count > 0 {
            unread.insert(root, u32::try_from(count).unwrap_or(u32::MAX));
        }
    }
    unread
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use matrix_sdk::{
        ruma::{
            event_id,
            events::receipt::{ReceiptThread, ReceiptType},
            room_id, user_id,
        },
        test_utils::mocks::MatrixMockServer,
    };
    use matrix_sdk_test::{event_factory::EventFactory, JoinedRoomBuilder};

    use super::*;
    use crate::test_support::{threaded_client, wait_until};

    #[tokio::test]
    async fn counts_unread_replies_per_thread_and_zeroes_after_the_thread_receipt() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let own = client.user_id().unwrap().to_owned();
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let root = event_id!("$root");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_timeline_event(f.text_msg("m1").sender(bob).event_id(event_id!("$m1")))
                    .add_timeline_event(f.text_msg("raiz").sender(bob).event_id(root))
                    .add_timeline_event(
                        f.text_msg("r1").sender(bob).event_id(event_id!("$r1")).in_thread(root, root),
                    )
                    .add_timeline_event(
                        f.text_msg("r2")
                            .sender(bob)
                            .event_id(event_id!("$r2"))
                            .in_thread(root, event_id!("$r1")),
                    ),
            )
            .await;
        let room = &room;

        wait_until(|| async move {
            unread_by_thread(room).await == HashMap::from([(root.to_owned(), 2)])
        })
        .await;
        // m1 e a raiz; as respostas contam só na thread.
        wait_until(|| async move { room.num_unread_messages() == 2 }).await;

        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_receipt(
                    f.read_receipts()
                        .add(event_id!("$r2"), &own, ReceiptType::Read, ReceiptThread::Thread(root.to_owned()))
                        .into_event(),
                ),
            )
            .await;

        wait_until(|| async move { unread_by_thread(room).await.is_empty() }).await;
    }

    #[tokio::test]
    async fn changed_in_ignores_other_rooms_and_wakes_for_its_room() {
        let reads = ThreadReads::default();
        let mut receiver = reads.subscribe();

        reads.notify(room_id!("!outra:b.c"));
        let other = tokio::time::timeout(
            Duration::from_millis(100),
            changed_in(&mut receiver, room_id!("!a:b.c")),
        )
        .await;
        assert!(other.is_err());

        reads.notify(room_id!("!a:b.c"));
        tokio::time::timeout(Duration::from_secs(1), changed_in(&mut receiver, room_id!("!a:b.c")))
            .await
            .expect("aviso da própria sala");
    }

    #[tokio::test]
    async fn changed_in_treats_a_lagged_channel_as_a_change() {
        let reads = ThreadReads::default();
        let mut receiver = reads.subscribe();

        for _ in 0..(CAPACITY + 10) {
            reads.notify(room_id!("!outra:b.c"));
        }

        tokio::time::timeout(Duration::from_secs(1), changed_in(&mut receiver, room_id!("!a:b.c")))
            .await
            .expect("atraso vale como mudança");
    }
}
