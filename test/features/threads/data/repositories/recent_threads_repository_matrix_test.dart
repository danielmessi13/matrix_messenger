import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/threads/data/repositories/recent_threads_repository_matrix.dart';
import 'package:matrix_messenger/features/threads/domain/models/recent_thread.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart' as rooms;
import 'package:matrix_messenger/src/rust/api/threads.dart' as bridge;

import '../../../../../testing/fakes/services/fake_matrix_service.dart';

void main() {
  late FakeMatrixService service;
  late RecentThreadsRepositoryMatrix repository;

  setUp(() {
    service = FakeMatrixService();
    repository = RecentThreadsRepositoryMatrix(service);
  });

  tearDown(() => service.dispose());

  test('converte RecentThreadsSnapshot em RecentThreads', () async {
    final received = repository.recentThreads.first;
    service.recentThreadsController.add(
      const bridge.RecentThreadsSnapshot(
        status: bridge.RecentThreadsStatus.ready,
        threads: [
          bridge.RecentThread(
            roomId: '!a:b.c',
            rootEventId: r'$r',
            root: rooms.LatestMessage(
              senderName: 'Bob',
              isOwn: false,
              kind: rooms.LatestMessageKind.encrypted,
              body: null,
              timestampMs: 1000,
            ),
            latestReply: null,
            replyCount: 2,
            activityMs: 5000,
          ),
        ],
      ),
    );

    expect(
      await received,
      RecentThreads(
        status: RecentThreadsStatus.ready,
        threads: [
          RecentThread(
            roomId: '!a:b.c',
            rootEventId: r'$r',
            root: LatestMessage(
              senderName: 'Bob',
              isOwn: false,
              kind: LatestMessageKind.encrypted,
              timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            ),
            replyCount: 2,
            activity: DateTime.fromMillisecondsSinceEpoch(5000),
          ),
        ],
      ),
    );
  });

  test('retry repassa ao serviço', () async {
    await repository.retry();

    expect(service.recentThreadsRetries, 1);
  });
}
