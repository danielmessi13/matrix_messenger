import 'dart:async';

import 'package:matrix_messenger/core/utils/result.dart';
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

  Result<void> inviteResult = const Result.ok(null);

  Completer<void>? inviteGate;

  final accepted = <String>[];

  final declined = <String>[];

  @override
  Future<Result<void>> acceptInvite(String roomId) async {
    accepted.add(roomId);
    await inviteGate?.future;
    return inviteResult;
  }

  @override
  Future<Result<void>> declineInvite(String roomId) async {
    declined.add(roomId);
    await inviteGate?.future;
    return inviteResult;
  }

  Future<void> dispose() async {
    await roomsController.close();
    await syncStateController.close();
  }
}
