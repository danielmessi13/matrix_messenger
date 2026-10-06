use matrix_sdk::{ruma::OwnedUserId, Room};
use tokio::sync::broadcast::error::RecvError;

use crate::api::timeline::TimelineError;

pub(crate) async fn watch(room: Room, mut emit: impl FnMut(Vec<String>) -> bool) {
    // Inscrito antes da emissão inicial para não perder aviso.
    let (_guard, mut receiver) = room.subscribe_to_typing_notifications();
    if !emit(Vec::new()) {
        return;
    }
    loop {
        let user_ids = match receiver.recv().await {
            Ok(user_ids) => user_ids,
            Err(RecvError::Lagged(_)) => continue,
            Err(RecvError::Closed) => return,
        };
        if !emit(names(&room, user_ids).await) {
            return;
        }
    }
}

async fn names(room: &Room, user_ids: Vec<OwnedUserId>) -> Vec<String> {
    let mut names = Vec::with_capacity(user_ids.len());
    for user_id in user_ids {
        let name = match room.get_member_no_sync(&user_id).await {
            Ok(Some(member)) => member.name().to_owned(),
            _ => user_id.localpart().to_owned(),
        };
        names.push(name);
    }
    names
}

// O SDK segura reenvios dentro do timeout de digitação; chamar a cada tecla é barato.
pub(crate) async fn set(room: &Room, typing: bool) -> Result<(), TimelineError> {
    Ok(room.typing_notice(typing).await?)
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use matrix_sdk::{
        ruma::{room_id, user_id},
        test_utils::mocks::MatrixMockServer,
    };
    use matrix_sdk_test::{event_factory::EventFactory, JoinedRoomBuilder};
    use tokio::{runtime::Handle, sync::mpsc::UnboundedReceiver};
    use wiremock::{
        matchers::{body_partial_json, method, path_regex},
        Mock, ResponseTemplate,
    };

    use crate::{test_support::threaded_client, threads::ThreadReads, timeline::TimelineHandle};

    async fn next(rx: &mut UnboundedReceiver<Vec<String>>) -> Vec<String> {
        tokio::time::timeout(Duration::from_secs(5), rx.recv())
            .await
            .unwrap()
            .unwrap()
    }

    #[tokio::test]
    async fn watch_typing_emits_others_names_and_drop_stops_it() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room_id = room_id!("!a:b.c");
        let bob = user_id!("@bob:b.c");
        let carol = user_id!("@carol:b.c");
        let f = EventFactory::new().room(room_id);
        let room = server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id)
                    .add_state_event(f.member(bob).display_name("Bob").sender(bob)),
            )
            .await;
        let own = room.own_user_id().to_owned();
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();

        handle.watch_typing(move |names| tx.send(names).is_ok());
        assert!(next(&mut rx).await.is_empty());

        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_typing(f.typing(vec![bob, &own, carol])),
            )
            .await;
        assert_eq!(next(&mut rx).await, ["Bob", "carol"]);

        server
            .sync_room(
                &client,
                JoinedRoomBuilder::new(room_id).add_typing(f.typing(vec![])),
            )
            .await;
        assert!(next(&mut rx).await.is_empty());

        drop(handle);
        assert!(tokio::time::timeout(Duration::from_secs(2), rx.recv())
            .await
            .unwrap()
            .is_none());
    }

    #[tokio::test]
    async fn set_typing_sends_the_typing_notice() {
        let server = MatrixMockServer::new().await;
        let client = threaded_client(&server).await;
        let room = server.sync_joined_room(&client, room_id!("!a:b.c")).await;
        Mock::given(method("PUT"))
            .and(path_regex(r"/rooms/.*/typing/"))
            .and(body_partial_json(serde_json::json!({ "typing": true })))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({})))
            .expect(1)
            .mount(server.server())
            .await;
        let handle = TimelineHandle::open(room, None, ThreadReads::default(), Handle::current())
            .await
            .unwrap();

        handle.set_typing(true).await.unwrap();
    }
}
