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

  String? roomLinkValue = 'https://matrix.to/#/!a:b.c?via=b.c';

  Completer<void>? roomLinkGate;

  Exception? roomLinkError;

  final roomLinkCalls = <String>[];

  @override
  Future<String?> roomLink(String roomId) async {
    roomLinkCalls.add(roomId);
    await roomLinkGate?.future;
    if (roomLinkError case final error?) throw error;
    return roomLinkValue;
  }

  Result<String> joinRoomResult = const Result.ok('!entrou:b.c');

  Completer<void>? joinRoomGate;

  final joinedTargets = <String>[];

  @override
  Future<Result<String>> joinRoom(String target) async {
    joinedTargets.add(target);
    await joinRoomGate?.future;
    return joinRoomResult;
  }

  Future<void> dispose() async {
    await roomsController.close();
    await syncStateController.close();
  }
}
