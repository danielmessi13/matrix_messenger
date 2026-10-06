import 'package:equatable/equatable.dart';

import '../../../domain/models/message_hit.dart';
import '../../../domain/models/message_search_failure.dart';

enum MessageSearchStatus { idle, loading, ready, failed }

final class MessageSearch extends Equatable {
  const MessageSearch({
    this.status = MessageSearchStatus.idle,
    this.hits = const [],
    this.nextBatch,
    this.loadingMore = false,
    this.failure,
  });

  final MessageSearchStatus status;

  final List<MessageHit> hits;

  final String? nextBatch;

  final bool loadingMore;

  final MessageSearchFailureType? failure;

  bool get hasMore => nextBatch != null;

  @override
  List<Object?> get props => [status, hits, nextBatch, loadingMore, failure];
}

final class EventFocus extends Equatable {
  const EventFocus(this.eventId, this.seq);

  final String eventId;

  final int seq;

  @override
  List<Object?> get props => [eventId, seq];
}
