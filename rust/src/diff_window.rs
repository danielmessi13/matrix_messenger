use std::future::Future;
use std::time::Duration;

use eyeball_im::{Vector, VectorDiff};
use futures_util::{Stream, StreamExt};

pub(crate) const DEBOUNCE: Duration = Duration::from_millis(100);

// Janela fixa a partir da primeira mudança: um fluxo contínuo de diffs não adia a emissão.
pub(crate) async fn next_batch<T: Clone, S>(stream: &mut S, items: &mut Vector<T>) -> bool
where
    S: Stream<Item = Vec<VectorDiff<T>>> + Unpin,
{
    let Some(diffs) = stream.next().await else {
        return false;
    };
    diffs.into_iter().for_each(|diff| diff.apply(items));
    let deadline = tokio::time::Instant::now() + DEBOUNCE;
    while let Ok(next) = tokio::time::timeout_at(deadline, stream.next()).await {
        let Some(diffs) = next else {
            return false;
        };
        diffs.into_iter().for_each(|diff| diff.apply(items));
    }
    true
}

// Cancelar a janela no meio é seguro: os diffs já aplicados ficam em `items` e saem na próxima emissão.
pub(crate) async fn next_batch_or<T: Clone, S>(
    stream: &mut S,
    items: &mut Vector<T>,
    signal: impl Future<Output = ()>,
) -> bool
where
    S: Stream<Item = Vec<VectorDiff<T>>> + Unpin,
{
    tokio::select! {
        more = next_batch(stream, items) => more,
        () = signal => true,
    }
}

#[cfg(test)]
mod tests {
    use eyeball_im::{Vector, VectorDiff};
    use futures_util::stream;

    use super::*;

    #[tokio::test]
    async fn next_batch_applies_everything_ready_in_the_window_and_reports_the_end() {
        let mut changes = stream::iter(vec![
            vec![VectorDiff::PushBack { value: 1 }],
            vec![
                VectorDiff::PushBack { value: 2 },
                VectorDiff::PushFront { value: 0 },
            ],
        ]);
        let mut items = Vector::new();

        assert!(!next_batch(&mut changes, &mut items).await);
        assert_eq!(items, Vector::from(vec![0, 1, 2]));
    }

    #[tokio::test]
    async fn next_batch_on_an_empty_stream_returns_false() {
        let mut changes = stream::iter(Vec::<Vec<VectorDiff<i32>>>::new());
        let mut items = Vector::new();

        assert!(!next_batch(&mut changes, &mut items).await);
        assert!(items.is_empty());
    }

    #[tokio::test]
    async fn next_batch_or_wakes_on_the_signal_without_diffs() {
        let mut changes = stream::pending::<Vec<VectorDiff<i32>>>();
        let mut items = Vector::new();

        assert!(next_batch_or(&mut changes, &mut items, async {}).await);
        assert!(items.is_empty());
    }

    #[tokio::test]
    async fn next_batch_or_reports_the_end_of_the_stream() {
        let mut changes = stream::iter(vec![vec![VectorDiff::PushBack { value: 1 }]]);
        let mut items = Vector::new();

        assert!(!next_batch_or(&mut changes, &mut items, std::future::pending()).await);
        assert_eq!(items, Vector::from(vec![1]));
    }
}
