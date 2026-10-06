use imagesize::ImageType;
use matrix_sdk::{
    attachment::BaseImageInfo,
    media::{MediaFormat, MediaRequestParameters, MediaThumbnailSettings},
    ruma::{
        events::room::{message::ImageMessageEventContent, MediaSource},
        UInt,
    },
    Client,
};
use mime::Mime;
use serde::{Deserialize, Serialize};

use crate::api::{
    media::{MediaError, MediaErrorKind},
    timeline::ImageContent,
};

const THUMBNAIL_SIDE: u32 = 640;

#[derive(Debug, Serialize, Deserialize)]
struct MediaRef {
    source: MediaSource,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    thumbnail: Option<MediaSource>,
}

fn to_u32(value: Option<UInt>) -> Option<u32> {
    value.and_then(|value| u32::try_from(u64::from(value)).ok())
}

pub(crate) fn image_content(image: &ImageMessageEventContent) -> ImageContent {
    let info = image.info.as_deref();
    let reference = MediaRef {
        source: image.source.clone(),
        thumbnail: info.and_then(|info| info.thumbnail_source.clone()),
    };
    ImageContent {
        filename: image.filename().to_owned(),
        caption: image.caption().map(ToOwned::to_owned),
        width: to_u32(info.and_then(|info| info.width)),
        height: to_u32(info.and_then(|info| info.height)),
        mimetype: info.and_then(|info| info.mimetype.clone()),
        media: serde_json::to_string(&reference).unwrap_or_default(),
    }
}

fn file(source: MediaSource) -> MediaRequestParameters {
    MediaRequestParameters {
        source,
        format: MediaFormat::File,
    }
}

pub(crate) async fn load(
    client: &Client,
    media: &str,
    thumbnail: bool,
) -> Result<Vec<u8>, MediaError> {
    let reference: MediaRef = serde_json::from_str(media).map_err(|error| MediaError {
        kind: MediaErrorKind::InvalidReference,
        message: error.to_string(),
    })?;
    let media = client.media();
    if thumbnail {
        let request = match (&reference.thumbnail, &reference.source) {
            (Some(source), _) => Some(file(source.clone())),
            (None, MediaSource::Plain(_)) => Some(MediaRequestParameters {
                source: reference.source.clone(),
                format: MediaFormat::Thumbnail(MediaThumbnailSettings::new(
                    UInt::from(THUMBNAIL_SIDE),
                    UInt::from(THUMBNAIL_SIDE),
                )),
            }),
            (None, MediaSource::Encrypted(_)) => None,
        };
        if let Some(request) = request {
            match media.get_media_content(&request, true).await {
                Ok(bytes) => return Ok(bytes),
                Err(error) => log::warn!("miniatura indisponível, baixando o original: {error}"),
            }
        }
    }
    Ok(media
        .get_media_content(&file(reference.source), true)
        .await?)
}

pub(crate) fn image_attachment(bytes: &[u8]) -> Option<(Mime, BaseImageInfo)> {
    let mime = match imagesize::image_type(bytes).ok()? {
        ImageType::Png => mime::IMAGE_PNG,
        ImageType::Jpeg => mime::IMAGE_JPEG,
        ImageType::Gif => mime::IMAGE_GIF,
        ImageType::Webp => "image/webp".parse().ok()?,
        _ => return None,
    };
    let size = imagesize::blob_size(bytes).ok();
    let info = BaseImageInfo {
        width: size.and_then(|size| UInt::try_from(size.width).ok()),
        height: size.and_then(|size| UInt::try_from(size.height).ok()),
        size: UInt::try_from(bytes.len()).ok(),
        ..Default::default()
    };
    Some((mime, info))
}

#[cfg(test)]
mod tests {
    use matrix_sdk::{
        ruma::{
            assign,
            events::room::{EncryptedFile, ImageInfo},
            mxc_uri, owned_mxc_uri,
        },
        test_utils::mocks::MatrixMockServer,
    };
    use serde_json::json;

    use super::*;
    use crate::test_support::png;

    fn encrypted_source() -> MediaSource {
        let file: EncryptedFile = serde_json::from_value(json!({
            "url": "mxc://b.c/cifrada",
            "key": {
                "kty": "oct",
                "key_ops": ["encrypt", "decrypt"],
                "alg": "A256CTR",
                "k": "qcHVMSgYg-71CauWBezXI5qkaRb0LuIy-Wx5kIaHMIA",
                "ext": true
            },
            "iv": "X85+XgHN+HEAAAAAAAAAAA",
            "hashes": { "sha256": "5qG4fFnbbVdlAB1Q72JDKwCagV6Dbkx9uds4rSak37c" },
            "v": "v2"
        }))
        .unwrap();
        MediaSource::Encrypted(Box::new(file))
    }

    #[test]
    fn image_content_maps_info_and_keeps_the_source_opaque() {
        let mut image = ImageMessageEventContent::plain(
            "foto.png".to_owned(),
            owned_mxc_uri!("mxc://b.c/foto"),
        )
        .info(Some(Box::new(assign!(ImageInfo::new(), {
            width: Some(UInt::from(800_u32)),
            height: Some(UInt::from(600_u32)),
            mimetype: Some("image/png".to_owned()),
            thumbnail_source: Some(encrypted_source()),
        }))));
        image.body = "olha isso".to_owned();
        image.filename = Some("foto.png".to_owned());

        let content = image_content(&image);

        assert_eq!(content.filename, "foto.png");
        assert_eq!(content.caption.as_deref(), Some("olha isso"));
        assert_eq!((content.width, content.height), (Some(800), Some(600)));
        assert_eq!(content.mimetype.as_deref(), Some("image/png"));
        let back: MediaRef = serde_json::from_str(&content.media).unwrap();
        assert!(matches!(back.source, MediaSource::Plain(uri) if uri == "mxc://b.c/foto"));
        assert!(
            matches!(back.thumbnail, Some(MediaSource::Encrypted(file)) if file.url == "mxc://b.c/cifrada")
        );
    }

    #[test]
    fn image_content_without_info_has_only_the_name() {
        let image = ImageMessageEventContent::new("gato.jpg".to_owned(), encrypted_source());

        let content = image_content(&image);

        assert_eq!(content.filename, "gato.jpg");
        assert_eq!(content.caption, None);
        assert_eq!(
            (content.width, content.height, content.mimetype),
            (None, None, None)
        );
        let back: MediaRef = serde_json::from_str(&content.media).unwrap();
        assert!(matches!(back.source, MediaSource::Encrypted(_)));
        assert!(back.thumbnail.is_none());
    }

    #[test]
    fn image_attachment_reads_type_and_size_from_the_header() {
        let (mime, info) = image_attachment(&png(40, 30)).unwrap();

        assert_eq!(mime, mime::IMAGE_PNG);
        assert_eq!(
            (info.width, info.height),
            (Some(UInt::from(40_u32)), Some(UInt::from(30_u32)))
        );
        assert_eq!(info.size, Some(UInt::from(png(40, 30).len() as u32)));
        assert!(image_attachment(b"%PDF-1.7 nao e imagem").is_none());
    }

    #[tokio::test]
    async fn load_falls_back_to_the_original_when_there_is_no_thumbnail() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;
        server.mock_media_download().ok_image().mount().await;
        server.mock_authed_media_download().ok_image().mount().await;
        let image =
            ImageMessageEventContent::plain("a.jpg".to_owned(), mxc_uri!("mxc://b.c/a").to_owned());

        let bytes = load(&client, &image_content(&image).media, true)
            .await
            .unwrap();

        assert_eq!(bytes, b"binaryjpegfullimagedata");
    }

    #[tokio::test]
    async fn load_with_a_broken_reference_is_invalid_reference() {
        let server = MatrixMockServer::new().await;
        let client = server.client_builder().build().await;

        let error = load(&client, "{}", false).await.unwrap_err();

        assert_eq!(error.kind, MediaErrorKind::InvalidReference);
    }
}
