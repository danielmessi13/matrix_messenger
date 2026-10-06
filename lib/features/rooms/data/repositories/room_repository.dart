import '../../../../core/utils/result.dart';
import '../../domain/models/room.dart';
import '../../domain/models/sync_state.dart';

abstract interface class RoomRepository {
  Stream<List<Room>> get rooms;

  Stream<SyncState> get syncState;

  Future<Result<void>> acceptInvite(String roomId);

  Future<Result<void>> declineInvite(String roomId);

  Future<String?> roomLink(String roomId);

  Future<Result<String>> joinRoom(String target);
}
