import 'package:equatable/equatable.dart';

import '../../domain/models/recent_thread.dart';

final class RecentThreadsState extends Equatable {
  const RecentThreadsState({
    this.status = RecentThreadsStatus.loading,
    this.threads = const [],
  });

  final RecentThreadsStatus status;

  final List<RecentThread> threads;

  @override
  List<Object?> get props => [status, threads];
}
