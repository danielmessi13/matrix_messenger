import '../../../../core/utils/result.dart';
import 'timeline_item.dart';

abstract interface class Conversation {
  /// Assinar uma vez só: cada assinatura abre um stream novo no Rust.
  Stream<ConversationSnapshot> get updates;

  Stream<List<String>> get typing;

  Future<Result<bool>> loadOlder();

  Future<Result<void>> send(String markdown);

  /// [inReplyTo] é o id do evento citado.
  Future<Result<void>> sendReply(String markdown, String inReplyTo);

  Future<Result<void>> sendImage(String path, {String? inReplyTo});

  Future<Result<void>> retry(String messageId);

  Future<Result<void>> cancel(String messageId);

  Future<Result<void>> toggleReaction(String messageId, String key);

  Future<void> markAsRead();

  Future<void> setTyping(bool typing);

  Future<Result<Conversation>> openThread(String rootEventId);

  void dispose();
}
