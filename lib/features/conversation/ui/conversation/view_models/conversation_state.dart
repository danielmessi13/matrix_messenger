import 'package:equatable/equatable.dart';

import '../../../domain/models/timeline_item.dart';
import 'message_search.dart';

enum ConversationStatus { opening, ready, failed }

const _unset = Object();

final class ConversationState extends Equatable {
  const ConversationState({
    this.status = ConversationStatus.opening,
    this.items = const [],
    this.reachedStart = false,
    this.loadingOlder = false,
    this.openThreadId,
    this.replyTo,
    this.focusRequest,
  });

  final ConversationStatus status;

  final List<TimelineItem> items;

  final bool reachedStart;

  final bool loadingOlder;

  final String? openThreadId;

  final MessageItem? replyTo;

  final FocusRequest? focusRequest;

  // `openThreadId`/`replyTo: null` limpam; sem o argumento, mantêm.
  ConversationState copyWith({
    ConversationStatus? status,
    List<TimelineItem>? items,
    bool? reachedStart,
    bool? loadingOlder,
    Object? openThreadId = _unset,
    Object? replyTo = _unset,
    FocusRequest? focusRequest,
  }) => ConversationState(
    status: status ?? this.status,
    items: items ?? this.items,
    reachedStart: reachedStart ?? this.reachedStart,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    openThreadId: identical(openThreadId, _unset)
        ? this.openThreadId
        : openThreadId as String?,
    replyTo: identical(replyTo, _unset)
        ? this.replyTo
        : replyTo as MessageItem?,
    focusRequest: focusRequest ?? this.focusRequest,
  );

  @override
  List<Object?> get props => [
    status,
    items,
    reachedStart,
    loadingOlder,
    openThreadId,
    replyTo,
    focusRequest,
  ];
}
