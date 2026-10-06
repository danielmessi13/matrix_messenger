use crate::{api::client::MatrixClient, media};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum MediaErrorKind {
    InvalidReference,
    Network,
    Unknown,
}

#[derive(Debug)]
pub struct MediaError {
    pub kind: MediaErrorKind,
    pub message: String,
}

impl From<matrix_sdk::Error> for MediaError {
    fn from(error: matrix_sdk::Error) -> Self {
        let kind = match error {
            matrix_sdk::Error::Http(_) => MediaErrorKind::Network,
            _ => MediaErrorKind::Unknown,
        };
        Self {
            kind,
            message: error.to_string(),
        }
    }
}

impl MatrixClient {
    pub async fn load_media(&self, media: String, thumbnail: bool) -> Result<Vec<u8>, MediaError> {
        media::load(&self.client, &media, thumbnail).await
    }
}
