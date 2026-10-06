import '../../../../core/utils/result.dart';
import '../../domain/models/message_hit.dart';
import '../../domain/models/new_room.dart';
import '../../domain/models/room.dart';
import '../../domain/models/sync_state.dart';
import '../../domain/models/user_check.dart';

abstract interface class RoomRepository {
  Stream<List<Room>> get rooms;

  Stream<SyncState> get syncState;

  Future<Result<void>> acceptInvite(String roomId);

  Future<Result<void>> declineInvite(String roomId);

  Future<Result<void>> leaveRoom(String roomId);

  Future<Result<void>> inviteUser(String roomId, String userId);

  Future<bool> canInvite(String roomId);

  Future<Result<CreatedRoom>> createRoom(NewRoom room);

  Future<UserCheck> checkUser(String userId);

  Future<String?> roomLink(String roomId);

  Future<Result<String>> joinRoom(String target);

  Future<Result<MessageSearchPage>> searchMessages(
    String term, {
    String? nextBatch,
  });
}
