use matrix_sdk::{
    encryption::{BackupDownloadStrategy, EncryptionSettings},
    Client, ClientBuilder,
};

use crate::threads::THREADING;

// Só busca no backup a chave de uma mensagem que falhou, em vez de baixar o backup inteiro.
pub(crate) fn client_builder() -> ClientBuilder {
    Client::builder()
        .with_threading_support(THREADING)
        .with_encryption_settings(EncryptionSettings {
            backup_download_strategy: BackupDownloadStrategy::AfterDecryptionFailure,
            ..Default::default()
        })
}
