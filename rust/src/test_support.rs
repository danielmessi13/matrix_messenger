use std::{future::Future, path::Path, time::Duration};

use matrix_sdk::{
    ruma::{owned_device_id, owned_user_id},
    test_utils::mocks::MatrixMockServer,
    Client, SessionMeta, SessionTokens,
};

use crate::{session_store, threads::THREADING};

pub(crate) fn temp_data_dir(name: &str) -> String {
    let dir = std::env::temp_dir()
        .join("matrix_messenger_tests")
        .join(name);
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.to_string_lossy().into_owned()
}

pub(crate) fn store_count(data_dir: &str) -> usize {
    std::fs::read_dir(session_store::stores_dir(data_dir)).map_or(0, Iterator::count)
}

pub(crate) async fn offline_client(store_path: &Path) -> Client {
    Client::builder()
        .homeserver_url("http://127.0.0.1:9")
        .sqlite_store(store_path, Some("segredo"))
        .build()
        .await
        .unwrap()
}

pub(crate) fn session_meta() -> SessionMeta {
    SessionMeta {
        user_id: owned_user_id!("@alice:example.org"),
        device_id: owned_device_id!("DEVICE"),
    }
}

pub(crate) fn tokens(refresh: &str) -> SessionTokens {
    SessionTokens {
        access_token: format!("access-{refresh}"),
        refresh_token: Some(refresh.into()),
    }
}

// O event cache já assina o sync; sem ele as contagens de thread não existem.
pub(crate) async fn threaded_client(server: &MatrixMockServer) -> Client {
    let client = server
        .client_builder()
        .on_builder(|builder| builder.with_threading_support(THREADING))
        .build()
        .await;
    client.event_cache().subscribe().unwrap();
    client
}

pub(crate) async fn wait_until<F, Fut>(mut ready: F)
where
    F: FnMut() -> Fut,
    Fut: Future<Output = bool>,
{
    for _ in 0..250 {
        if ready().await {
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("condição não atingida em 5 s");
}
