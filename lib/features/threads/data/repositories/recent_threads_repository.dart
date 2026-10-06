import '../../domain/models/recent_thread.dart';

abstract interface class RecentThreadsRepository {
  Stream<RecentThreads> get recentThreads;

  Future<void> retry();
}
