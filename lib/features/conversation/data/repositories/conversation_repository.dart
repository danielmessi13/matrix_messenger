import '../../../../core/utils/result.dart';
import '../../domain/models/conversation.dart';

abstract interface class ConversationRepository {
  Future<Result<Conversation>> open(String roomId);
}
