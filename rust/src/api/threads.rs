use crate::{
    api::{client::MatrixClient, rooms::LatestMessage},
    frb_generated::StreamSink,
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum RecentThreadsStatus {
    Loading,
    Ready,
    Failed,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecentThread {
    pub room_id: String,
    pub root_event_id: String,
    pub root: LatestMessage,
    pub latest_reply: Option<LatestMessage>,
    pub reply_count: u32,
    pub activity_ms: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RecentThreadsSnapshot {
    pub status: RecentThreadsStatus,
    pub threads: Vec<RecentThread>,
}

impl MatrixClient {
    pub fn watch_recent_threads(&self, sink: StreamSink<RecentThreadsSnapshot>) {
        self.recent_threads
            .watch(move |snapshot| sink.add(snapshot).is_ok());
    }

    pub fn retry_recent_threads(&self) {
        self.recent_threads.loader().load();
    }
}
