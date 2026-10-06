import 'dart:async';

import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation_failure.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';

class FakeConversation implements Conversation {
  late final snapshots = StreamController<ConversationSnapshot>.broadcast(
    onListen: () => listens++,
  );

  int listens = 0;

  final typingNames = StreamController<List<String>>.broadcast();
  final typingSent = <bool>[];

  // Chega ao início por padrão, para a tela não pedir páginas sem fim.
  Result<bool> loadOlderResult = const Result.ok(true);
  Completer<void>? loadOlderCompleter;
  int loadOlderCalls = 0;
  Result<void> sendResult = const Result.ok(null);
  final sent = <String>[];
  final sentReplies = <(String, String)>[];
  final sentImages = <(String, String?)>[];
  Result<void> sendImageResult = const Result.ok(null);
  Completer<void>? sendImageCompleter;
  // Simula o snapshot que a paginação traria.
  void Function()? onLoadOlder;
  final retried = <String>[];
  final cancelled = <String>[];
  final reacted = <(String, String)>[];
  Result<void> retryResult = const Result.ok(null);
  Result<void> cancelResult = const Result.ok(null);
  Result<void> reactResult = const Result.ok(null);
  int markAsReadCalls = 0;
  Result<Conversation>? threadResult;
  final openedThreads = <String>[];
  bool isDisposed = false;

  @override
  Stream<ConversationSnapshot> get updates => snapshots.stream;

  @override
  Future<Result<bool>> loadOlder() async {
    loadOlderCalls++;
    await loadOlderCompleter?.future;
    onLoadOlder?.call();
    return loadOlderResult;
  }

  @override
  Future<Result<void>> send(String markdown) async {
    sent.add(markdown);
    return sendResult;
  }

  @override
  Future<Result<void>> sendReply(String markdown, String inReplyTo) async {
    sentReplies.add((markdown, inReplyTo));
    return sendResult;
  }

  @override
  Future<Result<void>> sendImage(String path, {String? inReplyTo}) async {
    sentImages.add((path, inReplyTo));
    await sendImageCompleter?.future;
    return sendImageResult;
  }

  @override
  Future<Result<void>> retry(String messageId) async {
    retried.add(messageId);
    return retryResult;
  }

  @override
  Future<Result<void>> cancel(String messageId) async {
    cancelled.add(messageId);
    return cancelResult;
  }

  @override
  Future<Result<void>> toggleReaction(String messageId, String key) async {
    reacted.add((messageId, key));
    return reactResult;
  }

  @override
  Future<void> markAsRead() async => markAsReadCalls++;

  @override
  Stream<List<String>> get typing => typingNames.stream;

  @override
  Future<void> setTyping(bool typing) async => typingSent.add(typing);

  @override
  Future<Result<Conversation>> openThread(String rootEventId) async {
    openedThreads.add(rootEventId);
    return threadResult ?? Result.ok(FakeConversation());
  }

  @override
  void dispose() {
    isDisposed = true;
    snapshots.close();
    typingNames.close();
  }
}

class FakeConversationRepository implements ConversationRepository {
  FakeConversationRepository({FakeConversation? conversation})
    : conversation = conversation ?? FakeConversation();

  FakeConversation conversation;

  Exception? openFailure;

  Completer<void>? openCompleter;

  // Devolvido direto, sem passo assíncrono extra: o ViewModel retoma na primeira microtask após completar.
  Completer<Result<Conversation>>? pendingOpen;

  final openedRooms = <String>[];

  @override
  Future<Result<Conversation>> open(String roomId) {
    openedRooms.add(roomId);
    if (pendingOpen case final pending?) return pending.future;
    return _open();
  }

  Future<Result<Conversation>> _open() async {
    await openCompleter?.future;
    if (openFailure case final failure?) return Result.error(failure);
    return Result.ok(conversation);
  }

  static const notFound = ConversationFailure(
    ConversationFailureType.roomNotFound,
  );
}
