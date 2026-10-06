import '../../../../core/services/matrix_service.dart';
import '../../../../core/utils/result.dart';
import '../../../../src/rust/api/timeline.dart' as bridge;
import '../../domain/models/conversation.dart';
import '../../domain/models/conversation_failure.dart';
import '../../domain/models/timeline_item.dart';
import 'conversation_repository.dart';

class ConversationRepositoryMatrix implements ConversationRepository {
  ConversationRepositoryMatrix(this._service);

  final MatrixService _service;

  @override
  Future<Result<Conversation>> open(String roomId) async {
    switch (await _service.openTimeline(roomId)) {
      case Ok(:final value):
        return Result.ok(_MatrixConversation(value));
      case Error(:final error):
        return Result.error(_toFailure(error));
    }
  }
}

class _MatrixConversation implements Conversation {
  _MatrixConversation(this._timeline);

  final bridge.RoomTimeline _timeline;

  @override
  Stream<ConversationSnapshot> get updates => _timeline.watch().map(_toSnapshot);

  @override
  Future<Result<bool>> loadOlder() => _run(_timeline.paginateBackwards);

  @override
  Future<Result<void>> send(String markdown) =>
      _run(() => _timeline.sendMarkdown(body: markdown));

  @override
  Future<Result<void>> retry(String messageId) =>
      _run(() => _timeline.retry(itemId: messageId));

  @override
  Future<Result<void>> cancel(String messageId) =>
      _run(() => _timeline.cancel(itemId: messageId));

  @override
  Future<void> markAsRead() => _run(_timeline.markAsRead);

  @override
  Future<Result<Conversation>> openThread(String rootEventId) => _run(
    () async => _MatrixConversation(
      await _timeline.openThread(rootEventId: rootEventId),
    ),
  );

  @override
  void dispose() => _timeline.dispose();

  static Future<Result<T>> _run<T>(Future<T> Function() action) async {
    try {
      return Result.ok(await action());
    } on Exception catch (error) {
      return Result.error(_toFailure(error));
    }
  }
}

ConversationFailure _toFailure(Exception error) => switch (error) {
  bridge.TimelineError(:final kind, :final message) => ConversationFailure(
    switch (kind) {
      bridge.TimelineErrorKind.roomNotFound => ConversationFailureType.roomNotFound,
      bridge.TimelineErrorKind.messageNotFound =>
        ConversationFailureType.messageNotFound,
      bridge.TimelineErrorKind.network => ConversationFailureType.network,
      bridge.TimelineErrorKind.unknown => ConversationFailureType.unknown,
    },
    message,
  ),
  ConversationFailure() => error,
  _ => ConversationFailure(ConversationFailureType.unknown, '$error'),
};

ConversationSnapshot _toSnapshot(bridge.TimelineSnapshot snapshot) =>
    ConversationSnapshot(
      items: [
        for (final entry in snapshot.items)
          if (entry.dateDividerMs case final ms?)
            DateDividerItem(DateTime.fromMillisecondsSinceEpoch(ms))
          else if (entry.message case final message?)
            _toMessage(message),
      ],
      reachedStart: snapshot.reachedStart,
    );

MessageItem _toMessage(bridge.TimelineMessage message) => MessageItem(
  id: message.id,
  senderId: message.senderId,
  senderName: message.senderName,
  isOwn: message.isOwn,
  timestamp: DateTime.fromMillisecondsSinceEpoch(message.timestampMs),
  kind: _toKind(message.kind),
  body: message.body,
  edited: message.edited,
  sendState: switch (message.sendState) {
    bridge.SendState.sent => SendState.sent,
    bridge.SendState.sending => SendState.sending,
    bridge.SendState.failed => SendState.failed,
    bridge.SendState.rejected => SendState.rejected,
  },
  thread: switch (message.thread) {
    null => null,
    final thread => ThreadSummary(
      rootEventId: thread.rootEventId,
      replies: thread.replies,
      unread: thread.unread,
      latestSender: thread.latestSender,
      latestAt: switch (thread.latestTimestampMs) {
        null => null,
        final ms => DateTime.fromMillisecondsSinceEpoch(ms),
      },
    ),
  },
  replyTo: switch (message.replyTo) {
    null => null,
    final reply => ReplyPreview(
      state: switch (reply.state) {
        bridge.ReplyState.loading => ReplyState.loading,
        bridge.ReplyState.ready => ReplyState.ready,
        bridge.ReplyState.unavailable => ReplyState.unavailable,
      },
      senderName: reply.senderName,
      kind: switch (reply.kind) {
        null => null,
        final kind => _toKind(kind),
      },
      body: reply.body,
    ),
  },
  readBy: List.unmodifiable(message.readBy),
);

MessageKind _toKind(bridge.MessageKind kind) => switch (kind) {
  bridge.MessageKind.text => MessageKind.text,
  bridge.MessageKind.notice => MessageKind.notice,
  bridge.MessageKind.emote => MessageKind.emote,
  bridge.MessageKind.image => MessageKind.image,
  bridge.MessageKind.file => MessageKind.file,
  bridge.MessageKind.encrypted => MessageKind.encrypted,
  bridge.MessageKind.redacted => MessageKind.redacted,
  bridge.MessageKind.other => MessageKind.other,
};
