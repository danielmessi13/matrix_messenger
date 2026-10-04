use std::path::Path;

use matrix_sdk::{
    ruma::{owned_device_id, owned_user_id},
    Client, SessionMeta, SessionTokens,
};

use crate::session_store;

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
