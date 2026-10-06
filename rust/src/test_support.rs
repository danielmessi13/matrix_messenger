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

// A variável de ambiente tem prioridade sobre o .env da raiz do app.
pub(crate) fn env_var(name: &str) -> String {
    std::env::var(name)
        .ok()
        .or_else(|| dotenv_value(name))
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| panic!("defina {name} no ambiente ou no .env"))
}

fn dotenv_value(name: &str) -> Option<String> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../.env");
    std::fs::read_to_string(path)
        .ok()?
        .lines()
        .find_map(|line| {
            let (key, value) = line.split_once('=')?;
            (key.trim() == name).then(|| value.trim().to_owned())
        })
}

// Só assinatura e IHDR: basta para ler tipo e tamanho pelo cabeçalho.
pub(crate) fn png(width: u32, height: u32) -> Vec<u8> {
    let mut bytes = b"\x89PNG\r\n\x1a\n\0\0\0\x0dIHDR".to_vec();
    bytes.extend_from_slice(&width.to_be_bytes());
    bytes.extend_from_slice(&height.to_be_bytes());
    bytes.extend_from_slice(&[8, 6, 0, 0, 0, 0, 0, 0, 0]);
    bytes
}
