import '../../domain/models/room.dart';
import '../../domain/models/sync_state.dart';

abstract interface class RoomRepository {
  Stream<List<Room>> get rooms;

  Stream<SyncState> get syncState;
}
