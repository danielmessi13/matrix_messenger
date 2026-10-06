use matrix_sdk::{
    config::RequestConfig,
    ruma::{
        api::client::search::search_events::v3::{
            Categories, Criteria, OrderBy, Request, SearchKeys, SearchResult,
        },
        events::{
            room::message::Relation, AnyMessageLikeEvent, AnyTimelineEvent, MessageLikeEvent,
        },
        uint,
    },
};

use crate::{
    api::client::MatrixClient,
    room_list::{room_name, sender_name},
};

const PAGE_SIZE: u32 = 20;

#[derive(Debug, Clone, PartialEq)]
pub struct MessageSearchPage {
    pub hits: Vec<MessageHit>,
    pub next_batch: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct MessageHit {
    pub room_id: String,
    pub room_name: String,
    pub is_direct: bool,
    pub event_id: String,
    pub sender_name: String,
    pub is_own: bool,
    pub body: String,
    pub timestamp_ms: i64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum SearchErrorKind {
    Network,
    Unknown,
}

#[derive(Debug)]
pub struct SearchError {
    pub kind: SearchErrorKind,
    pub message: String,
}

impl From<matrix_sdk::HttpError> for SearchError {
    fn from(error: matrix_sdk::HttpError) -> Self {
        let kind = if error.client_api_error_kind().is_none() {
            SearchErrorKind::Network
        } else {
            SearchErrorKind::Unknown
        };
        Self {
            kind,
            message: error.to_string(),
        }
    }
}

impl MatrixClient {
    pub async fn search_messages(
        &self,
        term: String,
        next_batch: Option<String>,
    ) -> Result<MessageSearchPage, SearchError> {
        let mut criteria = Criteria::new(term);
        criteria.keys = Some(vec![SearchKeys::ContentBody]);
        criteria.order_by = Some(OrderBy::Recent);
        criteria.filter.limit = Some(PAGE_SIZE.into());
        criteria.event_context.before_limit = uint!(0);
        criteria.event_context.after_limit = uint!(0);
        let mut categories = Categories::new();
        categories.room_events = Some(criteria);
        let mut request = Request::new(categories);
        request.next_batch = next_batch;

        let config = RequestConfig::new().disable_retry();
        let response = self
            .client
            .send(request)
            .with_request_config(config)
            .await?;
        let events = response.search_categories.room_events;
        let mut hits = Vec::with_capacity(events.results.len());
        for result in events.results {
            if let Some(hit) = self.hit(result).await {
                hits.push(hit);
            }
        }
        Ok(MessageSearchPage {
            hits,
            next_batch: events.next_batch,
        })
    }

    async fn hit(&self, result: SearchResult) -> Option<MessageHit> {
        let AnyTimelineEvent::MessageLike(AnyMessageLikeEvent::RoomMessage(
            MessageLikeEvent::Original(event),
        )) = result.result?.deserialize().ok()?
        else {
            return None;
        };
        if matches!(event.content.relates_to, Some(Relation::Replacement(_))) {
            return None;
        }
        let room = self.client.get_room(&event.room_id);
        let (room_name, is_direct, sender_name) = match &room {
            Some(room) => (
                room_name(room).await,
                room.is_dm(),
                sender_name(room, &event.sender).await,
            ),
            None => (String::new(), false, event.sender.localpart().to_owned()),
        };
        Some(MessageHit {
            room_id: event.room_id.to_string(),
            room_name,
            is_direct,
            event_id: event.event_id.to_string(),
            sender_name,
            is_own: Some(event.sender.as_ref()) == self.client.user_id(),
            body: event.content.body().to_owned(),
            timestamp_ms: i64::from(event.origin_server_ts.0),
        })
    }
}

#[cfg(test)]
mod tests {
    use matrix_sdk::{
        ruma::{
            event_id, events::room::message::RoomMessageEventContentWithoutRelation, room_id,
            user_id,
        },
        test_utils::mocks::MatrixMockServer,
    };
    use matrix_sdk_test::{event_factory::EventFactory, JoinedRoomBuilder};
    use serde_json::{json, Value};
    use wiremock::{
        matchers::{method, path},
        Mock, ResponseTemplate,
    };

    use super::*;
    use crate::test_support::temp_data_dir;

    fn search_responds(template: ResponseTemplate) -> Mock {
        Mock::given(method("POST"))
            .and(path("/_matrix/client/v3/search"))
            .respond_with(template)
    }

    async fn sent_body(server: &MatrixMockServer) -> (Value, Option<String>) {
        let requests = server.server().received_requests().await.unwrap();
        let request = requests
            .iter()
            .find(|request| request.url.path().ends_with("/search"))
            .expect("search enviado");
        (
            serde_json::from_slice(&request.body).unwrap(),
            request.url.query().map(str::to_owned),
        )
    }

    #[tokio::test]
    async fn search_messages_reads_hits_and_next_batch() {
        let server = MatrixMockServer::new().await;
        let inner = server.client_builder().build().await;
        let room_id = room_id!("!geral:example.org");
        let bob = user_id!("@bob:example.org");
        let f = EventFactory::new().room(room_id);
        server
            .sync_room(
                &inner,
                JoinedRoomBuilder::new(room_id)
                    .add_state_event(f.room_name("Geral").sender(bob))
                    .add_state_event(f.member(bob).display_name("Roberto")),
            )
            .await;
        let client = MatrixClient::new(inner, temp_data_dir("search_hits"), None);
        let message = f
            .text_msg("deploy amanhã")
            .sender(bob)
            .event_id(event_id!("$msg"))
            .server_ts(1_000)
            .into_raw_timeline();
        let edit = f
            .text_msg("* deploy hoje")
            .edit(
                event_id!("$msg"),
                RoomMessageEventContentWithoutRelation::text_plain("deploy hoje"),
            )
            .sender(bob)
            .event_id(event_id!("$edit"))
            .into_raw_timeline();
        let other_room = EventFactory::new()
            .room(room_id!("!sumiu:example.org"))
            .text_msg("deploy antigo")
            .sender(user_id!("@ana:example.org"))
            .event_id(event_id!("$old"))
            .server_ts(500)
            .into_raw_timeline();
        search_responds(ResponseTemplate::new(200).set_body_json(json!({
            "search_categories": { "room_events": {
                "count": 3,
                "next_batch": "pagina-2",
                "results": [
                    { "rank": 1.0, "result": message },
                    { "rank": 0.9, "result": edit },
                    { "rank": 0.5, "result": other_room },
                ],
            }}
        })))
        .expect(1)
        .mount(server.server())
        .await;

        let page = client
            .search_messages("deploy".to_owned(), Some("pagina-1".to_owned()))
            .await
            .unwrap();

        assert_eq!(page.next_batch.as_deref(), Some("pagina-2"));
        assert_eq!(
            page.hits,
            vec![
                MessageHit {
                    room_id: room_id.to_string(),
                    room_name: "Geral".to_owned(),
                    is_direct: false,
                    event_id: "$msg".to_owned(),
                    sender_name: "Roberto".to_owned(),
                    is_own: false,
                    body: "deploy amanhã".to_owned(),
                    timestamp_ms: 1_000,
                },
                MessageHit {
                    room_id: "!sumiu:example.org".to_owned(),
                    room_name: String::new(),
                    is_direct: false,
                    event_id: "$old".to_owned(),
                    sender_name: "ana".to_owned(),
                    is_own: false,
                    body: "deploy antigo".to_owned(),
                    timestamp_ms: 500,
                },
            ]
        );
        let (body, query) = sent_body(&server).await;
        assert_eq!(query.as_deref(), Some("next_batch=pagina-1"));
        let criteria = &body["search_categories"]["room_events"];
        assert_eq!(criteria["search_term"], "deploy");
        assert_eq!(criteria["keys"], json!(["content.body"]));
        assert_eq!(criteria["order_by"], "recent");
        assert_eq!(criteria["filter"]["limit"], PAGE_SIZE);
    }

    #[tokio::test]
    async fn search_messages_maps_errors() {
        let cases = [
            (ResponseTemplate::new(500), SearchErrorKind::Network),
            (
                ResponseTemplate::new(400)
                    .set_body_json(json!({ "errcode": "M_UNKNOWN", "error": "x" })),
                SearchErrorKind::Unknown,
            ),
        ];
        for (index, (template, kind)) in cases.into_iter().enumerate() {
            let server = MatrixMockServer::new().await;
            let client = MatrixClient::new(
                server.client_builder().build().await,
                temp_data_dir(&format!("search_error_{index}")),
                None,
            );
            search_responds(template).mount(server.server()).await;

            let error = client
                .search_messages("deploy".to_owned(), None)
                .await
                .unwrap_err();

            assert_eq!(error.kind, kind, "caso {index}");
        }
    }
}
