import 'dart:async';

import 'package:matrix_messenger/features/threads/data/repositories/recent_threads_repository.dart';
import 'package:matrix_messenger/features/threads/domain/models/recent_thread.dart';

class FakeRecentThreadsRepository implements RecentThreadsRepository {
  final controller = StreamController<RecentThreads>.broadcast();

  var retries = 0;

  @override
  Stream<RecentThreads> get recentThreads => controller.stream;

  @override
  Future<void> retry() async => retries++;

  Future<void> dispose() => controller.close();
}
