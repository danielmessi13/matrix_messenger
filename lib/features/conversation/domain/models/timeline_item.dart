import 'package:equatable/equatable.dart';

enum MessageKind { text, notice, emote, image, file, encrypted, redacted, other }

enum SendState { sent, sending, failed, rejected }

enum ReplyState { loading, ready, unavailable }

class ReplyPreview extends Equatable {
  const ReplyPreview({
    required this.state,
    this.senderName,
    this.kind,
    this.body,
  });

  final ReplyState state;

  final String? senderName;

  final MessageKind? kind;

  final String? body;

  @override
  List<Object?> get props => [state, senderName, kind, body];
}

class ThreadSummary extends Equatable {
  const ThreadSummary({
    required this.rootEventId,
    required this.replies,
    this.latestSender,
    this.latestAt,
    this.unread = 0,
  });

  final String rootEventId;

  final int replies;

  final String? latestSender;

  final DateTime? latestAt;

  final int unread;

  @override
  List<Object?> get props => [
    rootEventId,
    replies,
    latestSender,
    latestAt,
    unread,
  ];
}

sealed class TimelineItem extends Equatable {
  const TimelineItem();
}

final class DateDividerItem extends TimelineItem {
  const DateDividerItem(this.day);

  final DateTime day;

  @override
  List<Object?> get props => [day];
}

final class MessageItem extends TimelineItem {
  const MessageItem({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.isOwn,
    required this.timestamp,
    required this.kind,
    this.body,
    this.edited = false,
    this.sendState = SendState.sent,
    this.thread,
    this.replyTo,
    this.readBy = const [],
  });

  final String id;

  final String senderId;

  final String senderName;

  final bool isOwn;

  final DateTime timestamp;

  final MessageKind kind;

  final String? body;

  final bool edited;

  final SendState sendState;

  final ThreadSummary? thread;

  final ReplyPreview? replyTo;

  final List<String> readBy;

  @override
  List<Object?> get props => [
    id,
    senderId,
    senderName,
    isOwn,
    timestamp,
    kind,
    body,
    edited,
    sendState,
    thread,
    replyTo,
    readBy,
  ];
}

class ConversationSnapshot extends Equatable {
  const ConversationSnapshot({required this.items, required this.reachedStart});

  final List<TimelineItem> items;

  final bool reachedStart;

  @override
  List<Object?> get props => [items, reachedStart];
}
