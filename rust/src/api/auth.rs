use std::{
    path::{Path, PathBuf},
    time::Duration,
};

use matrix_sdk::{
    authentication::oauth::{
        error::{
            OAuthAuthorizationCodeError, OAuthClientRegistrationError, OAuthDiscoveryError,
            RequestTokenError,
        },
        OAuthError,
    },
    ruma::api::error::ErrorKind,
    Client, ClientBuildError, HttpError,
};

use crate::{
    api::client::{run_blocking, MatrixClient},
    client_builder::client_builder,
    oidc_callback::CallbackError,
    session_store::{self, SavedAuth, StoredSession},
};

const DEVICE_DISPLAY_NAME: &str = "Matrix Messenger (desktop)";

// Por padrão, o SDK repete requisições com resposta 5xx ou 429 por até 15 minutos.
const LOGOUT_TIMEOUT: Duration = Duration::from_secs(10);

impl MatrixClient {
    pub async fn login(
        homeserver: String,
        username: String,
        password: String,
        data_dir: String,
        keep_signed_in: bool,
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

        finish_new_login(client, data_dir, store_name, passphrase, keep_signed_in).await
    }

    pub async fn restore_session(data_dir: String) -> Result<Option<MatrixClient>, AuthError> {
        let load_dir = data_dir.clone();
        let Some(stored) = run_blocking(move || session_store::load(&load_dir))
            .await
            .map_err(AuthError::storage)?
        else {
            return Ok(None);
        };

        let saved = stored.clone();
        let stores_dir = session_store::stores_dir(&data_dir);
        let client = client_builder()
            .homeserver_url(&stored.homeserver_url)
            .sqlite_store(
                stores_dir.join(&stored.store_name),
                Some(&stored.passphrase),
            )
            .handle_refresh_tokens()
            .build()
            .await?;
        client.restore_session(stored.auth.into_session()).await?;

        let store_name = stored.store_name;
        run_blocking(move || session_store::remove_stores_except(&stores_dir, Some(&store_name)))
            .await;

        Ok(Some(Self::new(client, data_dir, Some(saved))))
    }

    pub async fn logout(&self) -> Result<(), AuthError> {
        if let Some(vault) = self.vault.clone() {
            run_blocking(move || vault.forget())
                .await
                .map_err(AuthError::storage)?;
        }
        // Daqui em diante um UnknownToken vem do próprio logout, não de uma revogação.
        self.session_watcher.abort();
        self.rooms.stop().await;
        tokio::time::timeout(LOGOUT_TIMEOUT, self.client.logout())
            .await
            .ok();
        Ok(())
    }
}

pub(crate) async fn finish_new_login(
    client: Client,
    data_dir: String,
    store_name: String,
    passphrase: String,
    keep_signed_in: bool,
) -> Result<MatrixClient, AuthError> {
    let Some(auth) = client.session().and_then(SavedAuth::from_session) else {
        drop(client);
        remove_failed_store(session_store::stores_dir(&data_dir).join(&store_name)).await;
        return Err(AuthError::new(
            AuthErrorKind::Unknown,
            "login sem sessão".into(),
        ));
    };
    let stored = StoredSession {
        homeserver_url: client.homeserver().to_string(),
        store_name: store_name.clone(),
        passphrase,
        auth,
    };

    let (save_dir, to_save) = (data_dir.clone(), stored.clone());
    let saved = if keep_signed_in {
        run_blocking(move || session_store::save(&save_dir, &to_save))
            .await
            .is_ok()
    } else {
        // Se a sessão antiga ficasse no cofre, voltaria no próximo início sem o store, que é apagado logo abaixo.
        if let Err(error) = run_blocking(move || session_store::delete(&save_dir)).await {
            tokio::time::timeout(LOGOUT_TIMEOUT, client.logout())
                .await
                .ok();
            drop(client);
            remove_failed_store(session_store::stores_dir(&data_dir).join(&store_name)).await;
            return Err(AuthError::storage(error));
        }
        false
    };

    // Só com o novo login feito os stores de logins anteriores deixam de ser necessários.
    let stores_dir = session_store::stores_dir(&data_dir);
    run_blocking(move || session_store::remove_stores_except(&stores_dir, Some(&store_name))).await;

    Ok(MatrixClient::new(client, data_dir, saved.then_some(stored)))
}

async fn login_new_device(
    homeserver: &str,
    username: &str,
    password: &str,
    store_path: &Path,
    passphrase: &str,
) -> Result<Client, AuthError> {
    let client = client_builder()
        .server_name_or_homeserver_url(homeserver.trim())
        .sqlite_store(store_path, Some(passphrase))
        .handle_refresh_tokens()
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
pub(crate) async fn remove_failed_store(path: PathBuf) {
    for _ in 0..10 {
        let attempt = path.clone();
        match run_blocking(move || std::fs::remove_dir_all(attempt)).await {
            Ok(()) => return,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return,
            Err(_) => tokio::time::sleep(Duration::from_millis(100)).await,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthErrorKind {
    InvalidHomeserver,
    HomeserverUnreachable,
    InvalidCredentials,
    UserDeactivated,
    RateLimited,
    Storage,
    OidcNotSupported,
    AuthorizationDenied,
    TimedOut,
    Cancelled,
    Unknown,
}

#[derive(Debug)]
pub struct AuthError {
    pub kind: AuthErrorKind,
    pub message: String,
}

impl AuthError {
    pub(crate) fn new(kind: AuthErrorKind, message: String) -> Self {
        Self { kind, message }
    }

    pub(crate) fn storage(message: String) -> Self {
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

impl From<OAuthDiscoveryError> for AuthError {
    fn from(error: OAuthDiscoveryError) -> Self {
        let kind = match &error {
            OAuthDiscoveryError::NotSupported => AuthErrorKind::OidcNotSupported,
            OAuthDiscoveryError::Http(_) => AuthErrorKind::HomeserverUnreachable,
            _ => AuthErrorKind::Unknown,
        };
        Self::new(kind, error.to_string())
    }
}

impl From<OAuthError> for AuthError {
    fn from(error: OAuthError) -> Self {
        match error {
            OAuthError::Discovery(error) => error.into(),
            OAuthError::ClientRegistration(error) => {
                let kind = match &error {
                    OAuthClientRegistrationError::NotSupported
                    | OAuthClientRegistrationError::OAuth(RequestTokenError::ServerResponse(_)) => {
                        AuthErrorKind::OidcNotSupported
                    }
                    OAuthClientRegistrationError::OAuth(RequestTokenError::Request(_)) => {
                        AuthErrorKind::HomeserverUnreachable
                    }
                    _ => AuthErrorKind::Unknown,
                };
                Self::new(kind, error.to_string())
            }
            OAuthError::AuthorizationCode(OAuthAuthorizationCodeError::Cancelled) => {
                Self::new(AuthErrorKind::AuthorizationDenied, error.to_string())
            }
            error => Self::new(AuthErrorKind::Unknown, error.to_string()),
        }
    }
}

impl From<CallbackError> for AuthError {
    fn from(error: CallbackError) -> Self {
        match error {
            CallbackError::TimedOut => Self::new(
                AuthErrorKind::TimedOut,
                "nenhum retorno do navegador".into(),
            ),
            CallbackError::Io(error) => Self::new(AuthErrorKind::Unknown, error.to_string()),
        }
    }
}

impl From<matrix_sdk::Error> for AuthError {
    fn from(error: matrix_sdk::Error) -> Self {
        let error = match error {
            matrix_sdk::Error::OAuth(error) => return (*error).into(),
            error => error,
        };
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

    use crate::test_support::{env_var, offline_client, store_count, temp_data_dir};

    #[test]
    fn oauth_not_supported_maps_to_oidc_not_supported() {
        let error = AuthError::from(OAuthError::Discovery(OAuthDiscoveryError::NotSupported));
        assert_eq!(error.kind, AuthErrorKind::OidcNotSupported);
    }

    #[test]
    fn access_denied_maps_to_authorization_denied() {
        let error = AuthError::from(matrix_sdk::Error::from(OAuthError::AuthorizationCode(
            OAuthAuthorizationCodeError::Cancelled,
        )));
        assert_eq!(error.kind, AuthErrorKind::AuthorizationDenied);
    }

    #[test]
    fn unsupported_client_registration_maps_to_oidc_not_supported() {
        let error = AuthError::from(OAuthError::ClientRegistration(
            OAuthClientRegistrationError::NotSupported,
        ));
        assert_eq!(error.kind, AuthErrorKind::OidcNotSupported);
    }

    #[test]
    fn callback_errors_keep_their_kind() {
        assert_eq!(
            AuthError::from(CallbackError::TimedOut).kind,
            AuthErrorKind::TimedOut
        );
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
            true,
        )
        .await;

        assert_eq!(
            result.err().map(|e| e.kind),
            Some(AuthErrorKind::InvalidHomeserver)
        );
        assert_eq!(store_count(&data_dir), 0);
    }

    #[tokio::test]
    async fn logout_stops_session_watcher() {
        let client = Client::builder()
            .homeserver_url("http://127.0.0.1:9")
            .build()
            .await
            .unwrap();
        let client = MatrixClient::new(client, temp_data_dir("logout_watcher"), None);

        client.logout().await.unwrap();
        for _ in 0..10 {
            if client.session_watcher.is_finished() {
                break;
            }
            tokio::task::yield_now().await;
        }

        assert!(client.session_watcher.is_finished());
    }

    #[tokio::test]
    async fn finish_without_session_removes_the_new_store() {
        let data_dir = temp_data_dir("finish_without_session");
        let store_name = session_store::unique_store_name();
        let store_path = session_store::stores_dir(&data_dir).join(&store_name);
        let client = offline_client(&store_path).await;
        assert_eq!(store_count(&data_dir), 1);

        let result =
            finish_new_login(client, data_dir.clone(), store_name, "segredo".into(), true).await;

        assert!(result.is_err());
        assert_eq!(store_count(&data_dir), 0);
    }

    #[tokio::test]
    async fn restore_without_saved_session_returns_none() {
        let restored = MatrixClient::restore_session(temp_data_dir("no_session")).await;
        assert!(matches!(restored, Ok(None)));
    }

    /// Requer MATRIX_HOMESERVER, MATRIX_USERNAME e MATRIX_PASSWORD.
    #[tokio::test]
    #[ignore]
    async fn session_lifecycle_with_real_account() {
        let data_dir = temp_data_dir("real_account");

        let client = MatrixClient::login(
            env_var("MATRIX_HOMESERVER"),
            env_var("MATRIX_USERNAME"),
            env_var("MATRIX_PASSWORD"),
            data_dir.clone(),
            true,
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
    async fn login_without_keep_signed_in_is_not_restored() {
        let data_dir = temp_data_dir("real_not_kept");

        let client = MatrixClient::login(
            env_var("MATRIX_HOMESERVER"),
            env_var("MATRIX_USERNAME"),
            env_var("MATRIX_PASSWORD"),
            data_dir.clone(),
            false,
        )
        .await
        .unwrap_or_else(|e| panic!("login falhou: {:?} - {}", e.kind, e.message));
        assert!(!client.session_saved());

        assert!(matches!(
            MatrixClient::restore_session(data_dir).await,
            Ok(None)
        ));
        client
            .logout()
            .await
            .unwrap_or_else(|e| panic!("logout falhou: {}", e.message));
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
            true,
        )
        .await;

        assert_eq!(
            result.err().map(|e| e.kind),
            Some(AuthErrorKind::InvalidCredentials)
        );
        assert_eq!(store_count(&data_dir), 0);
    }
}
