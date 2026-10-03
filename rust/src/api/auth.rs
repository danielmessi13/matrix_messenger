use std::{
    mem::ManuallyDrop,
    path::{Path, PathBuf},
    time::Duration,
};

use flutter_rust_bridge::frb;
use matrix_sdk::{ruma::api::error::ErrorKind, Client, ClientBuildError, HttpError};
use tokio::runtime::Handle;

use crate::session_store::{self, StoredSession};

const DEVICE_DISPLAY_NAME: &str = "Matrix Messenger (desktop)";

// Por padrão, o SDK repete requisições com resposta 5xx ou 429 por até 15 minutos.
const LOGOUT_TIMEOUT: Duration = Duration::from_secs(10);

#[frb(opaque)]
pub struct MatrixClient {
    client: ManuallyDrop<Client>,
    runtime: Handle,
    data_dir: String,
    session_saved: bool,
}

impl Drop for MatrixClient {
    /// O finalizer do Dart roda fora do runtime Tokio, e o store SQLite do SDK precisa dele ao fechar.
    fn drop(&mut self) {
        let _guard = self.runtime.enter();
        // SAFETY: `client` não é mais acessado depois daqui; o próprio `MatrixClient` está sendo destruído.
        unsafe { ManuallyDrop::drop(&mut self.client) };
    }
}

impl MatrixClient {
    pub async fn login(
        homeserver: String,
        username: String,
        password: String,
        data_dir: String,
    ) -> Result<MatrixClient, AuthError> {
        let passphrase = session_store::new_passphrase().map_err(AuthError::storage)?;
        let stores_dir = session_store::stores_dir(&data_dir);
        let store_name = session_store::unique_store_name();
        let store_path = stores_dir.join(&store_name);

        let client =
            match login_new_device(&homeserver, &username, &password, &store_path, &passphrase)
                .await
            {
                Ok(client) => client,
                Err(error) => {
                    remove_failed_store(store_path).await;
                    return Err(error);
                }
            };

        let stored = StoredSession {
            homeserver_url: client.homeserver().to_string(),
            store_name: store_name.clone(),
            passphrase,
            session: client
                .matrix_auth()
                .session()
                .ok_or_else(|| AuthError::new(AuthErrorKind::Unknown, "login sem sessão".into()))?,
        };
        let save_dir = data_dir.clone();
        let session_saved = run_blocking(move || session_store::save(&save_dir, &stored))
            .await
            .is_ok();

        // Só com o novo login feito os stores de logins anteriores deixam de ser necessários.
        run_blocking(move || session_store::remove_stores_except(&stores_dir, Some(&store_name)))
            .await;

        Ok(Self::new(client, data_dir, session_saved))
    }

    pub async fn restore_session(data_dir: String) -> Result<Option<MatrixClient>, AuthError> {
        let load_dir = data_dir.clone();
        let Some(stored) = run_blocking(move || session_store::load(&load_dir))
            .await
            .map_err(AuthError::storage)?
        else {
            return Ok(None);
        };

        let stores_dir = session_store::stores_dir(&data_dir);
        let client = Client::builder()
            .homeserver_url(&stored.homeserver_url)
            .sqlite_store(
                stores_dir.join(&stored.store_name),
                Some(&stored.passphrase),
            )
            .build()
            .await?;
        client.restore_session(stored.session).await?;

        // Restos de logins anteriores que não puderam ser apagados na época.
        let store_name = stored.store_name;
        run_blocking(move || session_store::remove_stores_except(&stores_dir, Some(&store_name)))
            .await;

        Ok(Some(Self::new(client, data_dir, true)))
    }

    pub async fn logout(&self) -> Result<(), AuthError> {
        if self.session_saved {
            let data_dir = self.data_dir.clone();
            run_blocking(move || session_store::delete(&data_dir))
                .await
                .map_err(AuthError::storage)?;
        }
        tokio::time::timeout(LOGOUT_TIMEOUT, self.client.logout())
            .await
            .ok();
        Ok(())
    }

    #[frb(sync, getter)]
    pub fn user_id(&self) -> String {
        self.client
            .user_id()
            .map(ToString::to_string)
            .unwrap_or_default()
    }

    #[frb(sync, getter)]
    pub fn device_id(&self) -> String {
        self.client
            .device_id()
            .map(ToString::to_string)
            .unwrap_or_default()
    }

    #[frb(sync, getter)]
    pub fn session_saved(&self) -> bool {
        self.session_saved
    }

    fn new(client: Client, data_dir: String, session_saved: bool) -> Self {
        Self {
            client: ManuallyDrop::new(client),
            // Funções async do flutter_rust_bridge rodam no runtime Tokio dele.
            runtime: Handle::current(),
            data_dir,
            session_saved,
        }
    }
}

async fn login_new_device(
    homeserver: &str,
    username: &str,
    password: &str,
    store_path: &Path,
    passphrase: &str,
) -> Result<Client, AuthError> {
    let client = Client::builder()
        .server_name_or_homeserver_url(homeserver.trim())
        .sqlite_store(store_path, Some(passphrase))
        .build()
        .await?;

    client
        .matrix_auth()
        .login_username(username.trim(), password)
        .initial_device_display_name(DEVICE_DISPLAY_NAME)
        .await?;

    Ok(client)
}

// No Windows, o SQLite ainda pode estar fechando os arquivos logo após o drop do `Client`.
async fn remove_failed_store(path: PathBuf) {
    for _ in 0..10 {
        let attempt = path.clone();
        match run_blocking(move || std::fs::remove_dir_all(attempt)).await {
            Ok(()) => return,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return,
            Err(_) => tokio::time::sleep(Duration::from_millis(100)).await,
        }
    }
}

async fn run_blocking<T: Send + 'static>(task: impl FnOnce() -> T + Send + 'static) -> T {
    tokio::task::spawn_blocking(task)
        .await
        .unwrap_or_else(|error| std::panic::resume_unwind(error.into_panic()))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthErrorKind {
    InvalidHomeserver,
    HomeserverUnreachable,
    InvalidCredentials,
    UserDeactivated,
    RateLimited,
    Storage,
    Unknown,
}

#[derive(Debug)]
pub struct AuthError {
    pub kind: AuthErrorKind,
    pub message: String,
}

impl AuthError {
    fn new(kind: AuthErrorKind, message: String) -> Self {
        Self { kind, message }
    }

    fn storage(message: String) -> Self {
        Self::new(AuthErrorKind::Storage, message)
    }
}

impl From<ClientBuildError> for AuthError {
    fn from(error: ClientBuildError) -> Self {
        let kind = match &error {
            ClientBuildError::MissingHomeserver
            | ClientBuildError::InvalidServerName
            | ClientBuildError::Url(_) => AuthErrorKind::InvalidHomeserver,
            ClientBuildError::AutoDiscovery(_) | ClientBuildError::Http(_) => {
                AuthErrorKind::HomeserverUnreachable
            }
            ClientBuildError::SqliteStore(_) => AuthErrorKind::Storage,
            _ => AuthErrorKind::Unknown,
        };
        Self::new(kind, error.to_string())
    }
}

impl From<matrix_sdk::Error> for AuthError {
    fn from(error: matrix_sdk::Error) -> Self {
        let kind = match error.client_api_error_kind() {
            Some(ErrorKind::Forbidden) => AuthErrorKind::InvalidCredentials,
            Some(ErrorKind::UserDeactivated) => AuthErrorKind::UserDeactivated,
            Some(ErrorKind::LimitExceeded(_)) => AuthErrorKind::RateLimited,
            _ => match &error {
                // Falha de rede, ou resposta que não é um erro Matrix (proxy com 502, site comum).
                matrix_sdk::Error::Http(http)
                    if matches!(**http, HttpError::Reqwest(_) | HttpError::Api(_))
                        && http.as_client_api_error().is_none() =>
                {
                    AuthErrorKind::HomeserverUnreachable
                }
                _ => AuthErrorKind::Unknown,
            },
        };
        Self::new(kind, error.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_data_dir(name: &str) -> String {
        let dir = std::env::temp_dir()
            .join("matrix_messenger_tests")
            .join(name);
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir.to_string_lossy().into_owned()
    }

    fn store_count(data_dir: &str) -> usize {
        std::fs::read_dir(session_store::stores_dir(data_dir)).map_or(0, Iterator::count)
    }

    fn env_var(name: &str) -> String {
        std::env::var(name).unwrap_or_else(|_| panic!("defina {name}"))
    }

    #[test]
    fn invalid_server_name_maps_to_invalid_homeserver() {
        let error = AuthError::from(ClientBuildError::InvalidServerName);
        assert_eq!(error.kind, AuthErrorKind::InvalidHomeserver);
    }

    #[test]
    fn missing_homeserver_maps_to_invalid_homeserver() {
        let error = AuthError::from(ClientBuildError::MissingHomeserver);
        assert_eq!(error.kind, AuthErrorKind::InvalidHomeserver);
    }

    #[tokio::test]
    async fn login_with_malformed_homeserver_fails_without_network_or_leftovers() {
        let data_dir = temp_data_dir("malformed_homeserver");

        let result = MatrixClient::login(
            "isto não é um servidor".into(),
            "alice".into(),
            "senha".into(),
            data_dir.clone(),
        )
        .await;

        assert_eq!(
            result.err().map(|e| e.kind),
            Some(AuthErrorKind::InvalidHomeserver)
        );
        assert_eq!(store_count(&data_dir), 0);
    }

    #[tokio::test]
    async fn restore_without_saved_session_returns_none() {
        let restored = MatrixClient::restore_session(temp_data_dir("no_session")).await;
        assert!(matches!(restored, Ok(None)));
    }

    /// ```sh
    /// MATRIX_HOMESERVER=matrix.org MATRIX_USERNAME=... MATRIX_PASSWORD=... \
    ///   cargo test -- --ignored session_lifecycle_with_real_account
    /// ```
    #[tokio::test]
    #[ignore]
    async fn session_lifecycle_with_real_account() {
        let data_dir = temp_data_dir("real_account");

        let client = MatrixClient::login(
            env_var("MATRIX_HOMESERVER"),
            env_var("MATRIX_USERNAME"),
            env_var("MATRIX_PASSWORD"),
            data_dir.clone(),
        )
        .await
        .unwrap_or_else(|e| panic!("login falhou: {:?} - {}", e.kind, e.message));
        assert!(client.user_id().starts_with('@'));
        assert!(!client.device_id().is_empty());
        assert!(client.session_saved(), "cofre do SO indisponível");
        let device_id = client.device_id();
        drop(client);

        let restored = MatrixClient::restore_session(data_dir.clone())
            .await
            .unwrap_or_else(|e| panic!("restauração falhou: {:?} - {}", e.kind, e.message))
            .expect("sessão salva no login");
        assert_eq!(restored.device_id(), device_id);

        restored
            .logout()
            .await
            .unwrap_or_else(|e| panic!("logout falhou: {}", e.message));
        drop(restored);
        assert!(matches!(
            MatrixClient::restore_session(data_dir).await,
            Ok(None)
        ));
    }

    #[tokio::test]
    #[ignore]
    async fn login_with_wrong_password_returns_invalid_credentials() {
        let data_dir = temp_data_dir("wrong_password");

        let result = MatrixClient::login(
            env_var("MATRIX_HOMESERVER"),
            env_var("MATRIX_USERNAME"),
            "senha-errada-de-proposito".into(),
            data_dir.clone(),
        )
        .await;

        assert_eq!(
            result.err().map(|e| e.kind),
            Some(AuthErrorKind::InvalidCredentials)
        );
        assert_eq!(store_count(&data_dir), 0);
    }
}
