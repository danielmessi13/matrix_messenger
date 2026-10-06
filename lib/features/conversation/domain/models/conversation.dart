import '../../../../core/utils/result.dart';
import 'timeline_item.dart';

abstract interface class Conversation {
  /// Assinar uma vez só: cada assinatura abre um stream novo no Rust.
  Stream<ConversationSnapshot> get updates;

  Future<Result<bool>> loadOlder();

  Future<Result<void>> send(String markdown);

  Future<Result<void>> retry(String messageId);

  Future<Result<void>> cancel(String messageId);

  Future<void> markAsRead();

  Future<Result<Conversation>> openThread(String rootEventId);

  void dispose();
}
