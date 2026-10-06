import 'package:equatable/equatable.dart';

import '../../../domain/models/timeline_item.dart';

enum ConversationStatus { opening, ready, failed }

final class ConversationState extends Equatable {
  const ConversationState({
    this.status = ConversationStatus.opening,
    this.items = const [],
    this.reachedStart = false,
    this.loadingOlder = false,
    this.expandedThreads = const {},
  });

  final ConversationStatus status;

  final List<TimelineItem> items;

  final bool reachedStart;

  final bool loadingOlder;

  final Set<String> expandedThreads;

  ConversationState copyWith({
    ConversationStatus? status,
    List<TimelineItem>? items,
    bool? reachedStart,
    bool? loadingOlder,
    Set<String>? expandedThreads,
  }) => ConversationState(
    status: status ?? this.status,
    items: items ?? this.items,
    reachedStart: reachedStart ?? this.reachedStart,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    expandedThreads: expandedThreads ?? this.expandedThreads,
  );

  @override
  List<Object?> get props => [
    status,
    items,
    reachedStart,
    loadingOlder,
    expandedThreads,
  ];
}
