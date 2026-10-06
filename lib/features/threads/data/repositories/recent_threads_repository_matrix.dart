import '../../../../core/services/matrix_service.dart';
import '../../../../src/rust/api/threads.dart' as bridge;
import '../../../rooms/data/repositories/latest_message_mapper.dart';
import '../../domain/models/recent_thread.dart';
import 'recent_threads_repository.dart';

class RecentThreadsRepositoryMatrix implements RecentThreadsRepository {
  RecentThreadsRepositoryMatrix(this._service);

  final MatrixService _service;

  @override
  Stream<RecentThreads> get recentThreads =>
      _service.watchRecentThreads().map(_toRecentThreads);

  @override
  Future<void> retry() => _service.retryRecentThreads();

  RecentThreads _toRecentThreads(bridge.RecentThreadsSnapshot snapshot) =>
      RecentThreads(
        status: switch (snapshot.status) {
          bridge.RecentThreadsStatus.loading => RecentThreadsStatus.loading,
          bridge.RecentThreadsStatus.ready => RecentThreadsStatus.ready,
          bridge.RecentThreadsStatus.failed => RecentThreadsStatus.failed,
        },
        threads: List.unmodifiable(snapshot.threads.map(_toThread)),
      );

  RecentThread _toThread(bridge.RecentThread thread) => RecentThread(
    roomId: thread.roomId,
    rootEventId: thread.rootEventId,
    root: toLatestMessage(thread.root),
    latestReply: switch (thread.latestReply) {
      null => null,
      final reply => toLatestMessage(reply),
    },
    replyCount: thread.replyCount,
    activity: DateTime.fromMillisecondsSinceEpoch(thread.activityMs),
  );
}
