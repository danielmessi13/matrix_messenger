import 'package:equatable/equatable.dart';

enum MessageKind {
  text,
  notice,
  emote,
  image,
  file,
  encrypted,
  redacted,
  other,
}

enum SendState { sent, sending, failed, rejected }

enum ReplyState { loading, ready, unavailable }

class ReplyPreview extends Equatable {
  const ReplyPreview({
    required this.eventId,
    required this.state,
    this.isOwn = false,
    this.senderName,
    this.kind,
    this.body,
  });

  final String eventId;

  final ReplyState state;

  final bool isOwn;

  final String? senderName;

  final MessageKind? kind;

  final String? body;

  @override
  List<Object?> get props => [eventId, state, isOwn, senderName, kind, body];
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
    this.eventId,
    required this.senderId,
    required this.senderName,
    required this.isOwn,
    required this.timestamp,
    required this.kind,
    this.body,
    this.edited = false,
    this.sendState = SendState.sent,
    this.canReply = false,
    this.thread,
    this.replyTo,
    this.readBy = const [],
  });

  final String id;

  final String? eventId;

  final String senderId;

  final String senderName;

  final bool isOwn;

  final DateTime timestamp;

  final MessageKind kind;

  final String? body;

  final bool edited;

  final SendState sendState;

  final bool canReply;

  final ThreadSummary? thread;

  final ReplyPreview? replyTo;

  final List<String> readBy;

  @override
  List<Object?> get props => [
    id,
    eventId,
    senderId,
    senderName,
    isOwn,
    timestamp,
    kind,
    body,
    edited,
    sendState,
    canReply,
    thread,
    replyTo,
    readBy,
  ];
}

enum RoomEventKind {
  created,
  joined,
  left,
  invited,
  inviteDeclined,
  kicked,
  banned,
  unbanned,
  nameChanged,
  topicChanged,
  avatarChanged,
  encryptionEnabled,
  displayNameChanged,
}

final class RoomEventItem extends TimelineItem {
  const RoomEventItem({
    required this.id,
    required this.senderName,
    required this.isOwn,
    required this.timestamp,
    required this.kind,
    this.targetName,
    this.targetIsOwn = false,
    this.value,
  });

  final String id;

  final String senderName;

  final bool isOwn;

  final DateTime timestamp;

  final RoomEventKind kind;

  final String? targetName;

  final bool targetIsOwn;

  final String? value;

  @override
  List<Object?> get props => [
    id,
    senderName,
    isOwn,
    timestamp,
    kind,
    targetName,
    targetIsOwn,
    value,
  ];
}

class ConversationSnapshot extends Equatable {
  const ConversationSnapshot({
    required this.items,
    required this.reachedStart,
    this.paginating = false,
  });

  final List<TimelineItem> items;

  final bool reachedStart;

  final bool paginating;

  @override
  List<Object?> get props => [items, reachedStart, paginating];
}
