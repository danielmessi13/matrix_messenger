import 'package:equatable/equatable.dart';

import '../../../domain/models/timeline_item.dart';

enum ThreadStatus { loading, ready, failed }

final class ThreadState extends Equatable {
  const ThreadState({
    this.status = ThreadStatus.loading,
    this.replies = const [],
    this.reachedStart = false,
    this.loadingOlder = false,
  });

  final ThreadStatus status;

  final List<MessageItem> replies;

  final bool reachedStart;

  final bool loadingOlder;

  ThreadState copyWith({
    ThreadStatus? status,
    List<MessageItem>? replies,
    bool? reachedStart,
    bool? loadingOlder,
  }) => ThreadState(
    status: status ?? this.status,
    replies: replies ?? this.replies,
    reachedStart: reachedStart ?? this.reachedStart,
    loadingOlder: loadingOlder ?? this.loadingOlder,
  );

  @override
  List<Object?> get props => [status, replies, reachedStart, loadingOlder];
}
