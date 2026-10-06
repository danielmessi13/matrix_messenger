import 'package:equatable/equatable.dart';

import '../../../rooms/domain/models/room.dart';

enum RecentThreadsStatus { loading, ready, failed }

class RecentThread extends Equatable {
  const RecentThread({
    required this.roomId,
    required this.rootEventId,
    required this.root,
    this.latestReply,
    required this.replyCount,
    required this.activity,
  });

  final String roomId;

  final String rootEventId;

  final LatestMessage root;

  final LatestMessage? latestReply;

  final int replyCount;

  final DateTime activity;

  @override
  List<Object?> get props => [
    roomId,
    rootEventId,
    root,
    latestReply,
    replyCount,
    activity,
  ];
}

class RecentThreads extends Equatable {
  const RecentThreads({required this.status, required this.threads});

  final RecentThreadsStatus status;

  final List<RecentThread> threads;

  @override
  List<Object?> get props => [status, threads];
}
