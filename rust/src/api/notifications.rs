use crate::{
    api::{client::MatrixClient, rooms::LatestMessageKind},
    frb_generated::StreamSink,
};

#[derive(Debug, Clone, PartialEq)]
pub struct RoomNotification {
    pub room_id: String,
    pub room_name: String,
    pub is_direct: bool,
    pub is_invite: bool,
    pub sender_name: String,
    pub kind: LatestMessageKind,
    pub body: Option<String>,
    pub timestamp_ms: i64,
}

impl MatrixClient {
    // O stream termina sozinho quando o `Client` é destruído.
    pub fn watch_notifications(&self, sink: StreamSink<RoomNotification>) {
        let notifier = self.notifier.clone();
        let client = (*self.client).clone();
        self.runtime.spawn(async move {
            notifier.watch(&client, move |item| sink.add(item).is_ok()).await;
        });
    }
}
