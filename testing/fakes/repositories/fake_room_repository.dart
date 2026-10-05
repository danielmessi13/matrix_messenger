import 'dart:async';

import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/sync_state.dart';

class FakeRoomRepository implements RoomRepository {
  final roomsController = StreamController<List<Room>>.broadcast();

  final syncStateController = StreamController<SyncState>.broadcast();

  @override
  Stream<List<Room>> get rooms => roomsController.stream;

  @override
  Stream<SyncState> get syncState => syncStateController.stream;

  Future<void> dispose() async {
    await roomsController.close();
    await syncStateController.close();
  }
}
