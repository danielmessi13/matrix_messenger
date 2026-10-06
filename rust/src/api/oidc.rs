use std::{path::Path, time::Duration};

use flutter_rust_bridge::frb;
use matrix_sdk::{
    authentication::oauth::{
        registration::{ApplicationType, ClientMetadata, Localized, OAuthGrantType},
        ClientRegistrationData, CsrfToken, OAuthAuthorizationData,
    },
    ruma::serde::Raw,
    utils::UrlOrQuery,
    Client,
};
use tokio::{
    runtime::Handle,
    sync::{watch, Mutex},
};
use url::Url;

use crate::{
    api::auth::{finish_new_login, remove_failed_store, AuthError, AuthErrorKind, MatrixClient},
    client_builder::client_builder,
    oidc_callback::CallbackServer,
    session_store,
};

const CLIENT_URI: &str = "https://github.com/danielmessi13/matrix_messenger";
const CLIENT_NAME: &str = "Matrix Messenger";
const CALLBACK_TIMEOUT: Duration = Duration::from_secs(5 * 60);

#[frb(opaque)]
pub struct OidcLogin {
    authorization_url: String,
    cancelled: watch::Sender<bool>,
    pending: Mutex<Option<PendingLogin>>,
    runtime: Handle,
}

struct PendingLogin {
    client: Client,
    state: CsrfToken,
    callback: CallbackServer,
    data_dir: String,
    store_name: String,
    passphrase: String,
}

impl Drop for OidcLogin {
    /// Mesmo motivo do `Drop` do `MatrixClient`: o store SQLite precisa do runtime Tokio ao fechar.
    fn drop(&mut self) {
        let _guard = self.runtime.enter();
        if let Some(pending) = self.pending.get_mut().take() {
            let store_path = session_store::stores_dir(&pending.data_dir).join(&pending.store_name);
            drop(pending);
            self.runtime.spawn(remove_failed_store(store_path));
        }
    }
}

impl OidcLogin {
    pub async fn start(homeserver: String, data_dir: String) -> Result<OidcLogin, AuthError> {
        let passphrase = session_store::new_passphrase().map_err(AuthError::storage)?;
        let store_name = session_store::unique_store_name();
        let store_path = session_store::stores_dir(&data_dir).join(&store_name);

        let (client, callback, authorization) =
            match prepare(&homeserver, &store_path, &passphrase).await {
                Ok(prepared) => prepared,
                Err(error) => {
                    remove_failed_store(store_path).await;
                    return Err(error);
                }
            };

        Ok(Self {
            authorization_url: authorization.url.to_string(),
            cancelled: watch::Sender::new(false),
            pending: Mutex::new(Some(PendingLogin {
                client,
                state: authorization.state,
                callback,
                data_dir,
                store_name,
                passphrase,
            })),
            runtime: Handle::current(),
        })
    }

    #[frb(sync, getter)]
    pub fn authorization_url(&self) -> String {
        self.authorization_url.clone()
    }

    pub async fn complete(&self) -> Result<MatrixClient, AuthError> {
        let pending =
            self.pending.lock().await.take().ok_or_else(|| {
                AuthError::new(AuthErrorKind::Unknown, "login já concluído".into())
            })?;
        let store_path = session_store::stores_dir(&pending.data_dir).join(&pending.store_name);

        let mut cancelled = self.cancelled.subscribe();
        let query = tokio::select! {
            query = pending.callback.wait_for_query(pending.state.secret(), CALLBACK_TIMEOUT) => query.map_err(AuthError::from),
            _ = cancelled.wait_for(|cancelled| *cancelled) => {
                Err(AuthError::new(AuthErrorKind::Cancelled, "cancelado pelo usuário".into()))
            }
        };

        let finished = match query {
            Ok(query) => pending
                .client
                .oauth()
                .finish_login(UrlOrQuery::Query(query))
                .await
                .map_err(AuthError::from),
            Err(error) => {
                pending.client.oauth().abort_login(&pending.state).await;
                Err(error)
            }
        };

        match finished {
            Ok(()) => {
                finish_new_login(
                    pending.client,
                    pending.data_dir,
                    pending.store_name,
                    pending.passphrase,
                )
                .await
            }
            Err(error) => {
                drop(pending);
                remove_failed_store(store_path).await;
                Err(error)
            }
        }
    }

    pub async fn cancel(&self) {
        self.cancelled.send_replace(true);
    }
}

async fn prepare(
    homeserver: &str,
    store_path: &Path,
    passphrase: &str,
) -> Result<(Client, CallbackServer, OAuthAuthorizationData), AuthError> {
    let client = client_builder()
        .server_name_or_homeserver_url(homeserver.trim())
        .sqlite_store(store_path, Some(passphrase))
        .handle_refresh_tokens()
        .build()
        .await?;
    client.oauth().server_metadata().await?;

    let callback = CallbackServer::bind()
        .await
        .map_err(|e| AuthError::new(AuthErrorKind::Unknown, format!("loopback: {e}")))?;
    let redirect_uri = callback.redirect_uri().clone();
    let authorization = client
        .oauth()
        .login(
            redirect_uri.clone(),
            None,
            Some(registration_data(redirect_uri)?),
            None,
        )
        .build()
        .await?;

    Ok((client, callback, authorization))
}

fn registration_data(redirect_uri: Url) -> Result<ClientRegistrationData, AuthError> {
    let client_uri = Url::parse(CLIENT_URI).expect("CLIENT_URI válida");
    let mut metadata = ClientMetadata::new(
        ApplicationType::Native,
        vec![OAuthGrantType::AuthorizationCode {
            redirect_uris: vec![redirect_uri],
        }],
        Localized::new(client_uri, []),
    );
    metadata.client_name = Some(Localized::new(CLIENT_NAME.to_owned(), []));
    let raw = Raw::new(&metadata)
        .map_err(|e| AuthError::new(AuthErrorKind::Unknown, format!("metadata: {e}")))?;
    Ok(raw.into())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{offline_client, store_count, temp_data_dir};

    #[tokio::test]
    async fn start_with_malformed_homeserver_fails_without_leftovers() {
        let data_dir = temp_data_dir("oidc_malformed");

        let result = OidcLogin::start("isto não é um servidor".into(), data_dir.clone()).await;

        assert_eq!(
            result.err().map(|e| e.kind),
            Some(AuthErrorKind::InvalidHomeserver)
        );
        assert_eq!(store_count(&data_dir), 0);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn dropping_without_complete_removes_the_store() {
        let data_dir = temp_data_dir("oidc_dropped");
        let store_name = session_store::unique_store_name();
        let store_path = session_store::stores_dir(&data_dir).join(&store_name);
        let login = OidcLogin {
            authorization_url: String::new(),
            cancelled: watch::Sender::new(false),
            pending: Mutex::new(Some(PendingLogin {
                client: offline_client(&store_path).await,
                state: CsrfToken::new("xyz".into()),
                callback: CallbackServer::bind().await.unwrap(),
                data_dir: data_dir.clone(),
                store_name,
                passphrase: "segredo".into(),
            })),
            runtime: Handle::current(),
        };

        std::thread::spawn(move || drop(login)).join().unwrap();
        for _ in 0..50 {
            if store_count(&data_dir) == 0 {
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }

        assert_eq!(store_count(&data_dir), 0);
    }

    #[tokio::test]
    #[ignore]
    async fn oidc_start_and_cancel_against_matrix_org() {
        let data_dir = temp_data_dir("oidc_cancel");

        let login = OidcLogin::start("matrix.org".into(), data_dir.clone())
            .await
            .unwrap_or_else(|e| panic!("start falhou: {:?} - {}", e.kind, e.message));
        let url = Url::parse(&login.authorization_url()).unwrap();
        let query: Vec<(String, String)> = url.query_pairs().into_owned().collect();
        let param = |name: &str| {
            query
                .iter()
                .find(|(k, _)| k == name)
                .map(|(_, v)| v.as_str())
        };

        assert_eq!(url.host_str(), Some("account.matrix.org"));
        assert_eq!(param("code_challenge_method"), Some("S256"));
        assert!(param("redirect_uri")
            .unwrap()
            .starts_with("http://127.0.0.1:"));

        login.cancel().await;
        let result = login.complete().await;
        assert_eq!(result.err().map(|e| e.kind), Some(AuthErrorKind::Cancelled));
        drop(login);
        assert_eq!(store_count(&data_dir), 0);
    }

    /// Abra a URL impressa no navegador e entre com uma conta do matrix.org (rodar com `--nocapture`).
    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn oidc_full_flow_interactive() {
        let data_dir = temp_data_dir("oidc_interactive");

        let login = OidcLogin::start("matrix.org".into(), data_dir.clone())
            .await
            .unwrap();
        println!("\nAbra no navegador:\n{}\n", login.authorization_url());
        let client = login
            .complete()
            .await
            .unwrap_or_else(|e| panic!("login falhou: {:?} - {}", e.kind, e.message));
        assert!(client.user_id().starts_with('@'));
        assert!(client.session_saved(), "cofre do SO indisponível");

        let refresh_before = saved_refresh_token(&data_dir);
        client.inner().oauth().refresh_access_token().await.unwrap();
        let mut refresh_after = saved_refresh_token(&data_dir);
        for _ in 0..50 {
            if refresh_after != refresh_before {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
            refresh_after = saved_refresh_token(&data_dir);
        }
        assert_ne!(
            refresh_after, refresh_before,
            "token renovado não foi regravado no cofre"
        );

        let device_id = client.device_id();
        drop(client);
        let restored = MatrixClient::restore_session(data_dir.clone())
            .await
            .unwrap()
            .unwrap();
        assert_eq!(restored.device_id(), device_id);
        restored.logout().await.unwrap();
    }

    fn saved_refresh_token(data_dir: &str) -> Option<String> {
        match session_store::load(data_dir).unwrap()?.auth {
            session_store::SavedAuth::OAuth { user, .. } => user.tokens.refresh_token,
            session_store::SavedAuth::Password(_) => None,
        }
    }
}
