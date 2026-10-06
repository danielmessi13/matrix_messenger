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
    this.paginating = false,
    this.olderFailed = false,
    this.openThreadId,
    this.replyTo,
    this.focusRequest,
  });

  final ConversationStatus status;

  final List<TimelineItem> items;

  final bool reachedStart;

  final bool paginating;

  // Falha não se repete sozinha; só o botão pede de novo.
  final bool olderFailed;

  final String? openThreadId;

  final MessageItem? replyTo;

  final FocusRequest? focusRequest;

  // `openThreadId`/`replyTo: null` limpam; sem o argumento, mantêm.
  ConversationState copyWith({
    ConversationStatus? status,
    List<TimelineItem>? items,
    bool? reachedStart,
    bool? paginating,
    bool? olderFailed,
    Object? openThreadId = _unset,
    Object? replyTo = _unset,
    FocusRequest? focusRequest,
  }) => ConversationState(
    status: status ?? this.status,
    items: items ?? this.items,
    reachedStart: reachedStart ?? this.reachedStart,
    paginating: paginating ?? this.paginating,
    olderFailed: olderFailed ?? this.olderFailed,
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
    paginating,
    olderFailed,
    openThreadId,
    replyTo,
    focusRequest,
  ];
}
