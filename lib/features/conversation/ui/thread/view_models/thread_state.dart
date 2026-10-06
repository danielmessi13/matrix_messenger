import 'package:equatable/equatable.dart';

import '../../../domain/models/timeline_item.dart';
import '../../conversation/view_models/message_search.dart';

enum ThreadStatus { loading, ready, failed }

const _unset = Object();

final class ThreadState extends Equatable {
  const ThreadState({
    this.status = ThreadStatus.loading,
    this.replies = const [],
    this.reachedStart = false,
    this.loadingOlder = false,
    this.replyTo,
    this.focusRequest,
  });

  final ThreadStatus status;

  final List<MessageItem> replies;

  final bool reachedStart;

  final bool loadingOlder;

  final MessageItem? replyTo;

  final FocusRequest? focusRequest;

  // `replyTo: null` limpa; sem o argumento, mantém.
  ThreadState copyWith({
    ThreadStatus? status,
    List<MessageItem>? replies,
    bool? reachedStart,
    bool? loadingOlder,
    Object? replyTo = _unset,
    FocusRequest? focusRequest,
  }) => ThreadState(
    status: status ?? this.status,
    replies: replies ?? this.replies,
    reachedStart: reachedStart ?? this.reachedStart,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    replyTo: identical(replyTo, _unset)
        ? this.replyTo
        : replyTo as MessageItem?,
    focusRequest: focusRequest ?? this.focusRequest,
  );

  @override
  List<Object?> get props => [
    status,
    replies,
    reachedStart,
    loadingOlder,
    replyTo,
    focusRequest,
  ];
}
