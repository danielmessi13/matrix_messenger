use futures_util::StreamExt;
use matrix_sdk::{
    encryption::{
        recovery::{RecoveryError as SdkRecoveryError, RecoveryState},
        secret_storage::SecretStorageError,
    },
    Client,
};
use tokio::runtime::Handle;

use crate::{api::client::MatrixClient, frb_generated::StreamSink};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryStatus {
    Unknown,
    Enabled,
    Disabled,
    /// A conta tem backup, mas este dispositivo ainda não tem a chave para abri-lo.
    Incomplete,
}

impl From<RecoveryState> for RecoveryStatus {
    fn from(state: RecoveryState) -> Self {
        match state {
            RecoveryState::Unknown => Self::Unknown,
            RecoveryState::Enabled => Self::Enabled,
            RecoveryState::Disabled => Self::Disabled,
            RecoveryState::Incomplete => Self::Incomplete,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RecoveryErrorKind {
    InvalidKey,
    Network,
    /// Já existe um backup no servidor, criado por outro app com outra chave.
    BackupExists,
    /// O servidor pediu a senha (UIA) para subir o cross-signing.
    AuthRequired,
    Unknown,
}

#[derive(Debug)]
pub struct RecoveryError {
    pub kind: RecoveryErrorKind,
    pub message: String,
}

impl From<SdkRecoveryError> for RecoveryError {
    fn from(error: SdkRecoveryError) -> Self {
        let kind = match &error {
            SdkRecoveryError::BackupExistsOnServer => RecoveryErrorKind::BackupExists,
            SdkRecoveryError::Sdk(sdk) if sdk.as_uiaa_response().is_some() => {
                RecoveryErrorKind::AuthRequired
            }
            SdkRecoveryError::SecretStorage(SecretStorageError::SecretStorageKey(_)) => {
                RecoveryErrorKind::InvalidKey
            }
            SdkRecoveryError::Sdk(matrix_sdk::Error::Http(_))
            | SdkRecoveryError::SecretStorage(SecretStorageError::Sdk(matrix_sdk::Error::Http(
                _,
            ))) => RecoveryErrorKind::Network,
            _ => RecoveryErrorKind::Unknown,
        };
        Self {
            kind,
            message: error.to_string(),
        }
    }
}

pub(crate) async fn recover(client: &Client, recovery_key: &str) -> Result<(), RecoveryError> {
    client
        .encryption()
        .recovery()
        .recover(recovery_key.trim())
        .await
        .map_err(Into::into)
}

// Cada enable() cria um secret storage novo e invalida a chave anterior.
pub(crate) async fn setup_recovery(client: &Client) -> Result<String, RecoveryError> {
    let encryption = client.encryption();
    encryption
        .bootstrap_cross_signing_if_needed(None)
        .await
        .map_err(SdkRecoveryError::from)?;
    encryption
        .recovery()
        .enable()
        .wait_for_backups_to_upload()
        .await
        .map_err(Into::into)
}

// O stream termina sozinho quando o `Client` é destruído.
pub(crate) fn watch(
    client: &Client,
    runtime: &Handle,
    mut emit: impl FnMut(RecoveryStatus) -> bool + Send + 'static,
) {
    let mut states = client.encryption().recovery().state_stream();
    runtime.spawn(async move {
        while let Some(state) = states.next().await {
            if !emit(state.into()) {
                return;
            }
        }
    });
}

impl MatrixClient {
    pub fn watch_recovery(&self, sink: StreamSink<RecoveryStatus>) {
        watch(&self.client, &self.runtime, move |status| {
            sink.add(status).is_ok()
        });
    }

    pub async fn recover(&self, recovery_key: String) -> Result<(), RecoveryError> {
        recover(&self.client, &recovery_key).await
    }

    pub async fn setup_recovery(&self) -> Result<String, RecoveryError> {
        setup_recovery(&self.client).await
    }
}

#[cfg(test)]
mod tests {
    use matrix_sdk::encryption::recovery::RecoveryError as SdkError;
    use matrix_sdk::{
        ruma::{
            events::secret_storage::key::{
                SecretStorageEncryptionAlgorithm, SecretStorageKeyEventContent,
                SecretStorageV1AesHmacSha2Properties,
            },
            serde::Base64,
        },
        test_utils::mocks::MatrixMockServer,
    };
    use serde_json::json;
    use tokio::sync::mpsc;
    use wiremock::{
        matchers::{method, path_regex},
        Mock, ResponseTemplate,
    };

    use super::*;

    #[tokio::test]
    async fn invalid_key_is_reported_as_invalid_key() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        let user_id = client.user_id().unwrap();
        server
            .mock_get_default_secret_storage_key()
            .ok(user_id, "abc")
            .mount()
            .await;
        server
            .mock_get_secret_storage_key()
            .ok(
                user_id,
                &SecretStorageKeyEventContent::new(
                    "abc".into(),
                    SecretStorageEncryptionAlgorithm::V1AesHmacSha2(
                        SecretStorageV1AesHmacSha2Properties::new(
                            Some(Base64::parse("xv5b6/p3ExEw++wTyfSHEg==").unwrap()),
                            Some(
                                Base64::parse("ujBBbXahnTAMkmPUX2/0+VTfUh63pGyVRuBcDMgmJC8=")
                                    .unwrap(),
                            ),
                        ),
                    ),
                ),
            )
            .mount()
            .await;

        let error = recover(&client, "chave errada").await.unwrap_err();

        assert_eq!(error.kind, RecoveryErrorKind::InvalidKey);
    }

    #[tokio::test]
    async fn watch_emits_the_current_state_first() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        let (sender, mut receiver) = mpsc::unbounded_channel();

        watch(&client, &Handle::current(), move |status| {
            sender.send(status).is_ok()
        });

        assert_eq!(
            receiver.recv().await,
            Some(RecoveryStatus::from(client.encryption().recovery().state()))
        );
    }

    #[test]
    fn incomplete_state_maps_to_incomplete() {
        assert_eq!(
            RecoveryStatus::from(RecoveryState::Incomplete),
            RecoveryStatus::Incomplete
        );
    }

    // O bootstrap pede a lista de chaves e sobe as chaves do dispositivo antes do cross-signing.
    async fn mount_device_keys(server: &MatrixMockServer) {
        server.mock_query_keys().ok().mount().await;
        server.mock_upload_keys().ok().mount().await;
    }

    #[tokio::test]
    async fn setup_returns_a_recovery_key() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        mount_device_keys(&server).await;
        server.mock_upload_cross_signing_keys().ok().mount().await;
        server
            .mock_upload_cross_signing_signatures()
            .ok()
            .mount()
            .await;
        server.mock_room_keys_version().none().mount().await;
        server.mock_add_room_keys_version().ok().mount().await;
        Mock::given(method("PUT"))
            .and(path_regex(r"/account_data/"))
            .respond_with(ResponseTemplate::new(200).set_body_json(json!({})))
            .mount(server.server())
            .await;
        Mock::given(method("GET"))
            .and(path_regex(r"/account_data/"))
            .respond_with(
                ResponseTemplate::new(404)
                    .set_body_json(json!({ "errcode": "M_NOT_FOUND", "error": "not found" })),
            )
            .mount(server.server())
            .await;

        let key = setup_recovery(&client).await.unwrap();

        let groups: Vec<&str> = key.split_whitespace().collect();
        assert_eq!(groups.len(), 12);
        assert!(groups.iter().all(|group| group.len() == 4));
    }

    #[tokio::test]
    async fn uiaa_on_cross_signing_is_auth_required() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        mount_device_keys(&server).await;
        server.mock_upload_cross_signing_keys().uiaa().mount().await;

        let error = setup_recovery(&client).await.unwrap_err();

        assert_eq!(error.kind, RecoveryErrorKind::AuthRequired);
    }

    #[tokio::test]
    async fn backup_from_another_app_is_backup_exists() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        mount_device_keys(&server).await;
        server.mock_upload_cross_signing_keys().ok().mount().await;
        server
            .mock_upload_cross_signing_signatures()
            .ok()
            .mount()
            .await;
        server.mock_room_keys_version().exists().mount().await;

        let error = setup_recovery(&client).await.unwrap_err();

        assert_eq!(error.kind, RecoveryErrorKind::BackupExists);
    }

    #[test]
    fn backup_exists_on_server_maps_to_backup_exists() {
        assert_eq!(
            RecoveryError::from(SdkError::BackupExistsOnServer).kind,
            RecoveryErrorKind::BackupExists
        );
    }
}
