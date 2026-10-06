use futures_util::StreamExt;
use matrix_sdk::{
    encryption::{
        recovery::{RecoveryError as SdkRecoveryError, RecoveryState},
        secret_storage::SecretStorageError,
    },
    Client,
};
use tokio::runtime::Handle;

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

#[cfg(test)]
mod tests {
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
    use tokio::sync::mpsc;

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
}
