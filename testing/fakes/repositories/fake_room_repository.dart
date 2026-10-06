import 'dart:async';

import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/rooms/domain/models/message_hit.dart';
import 'package:matrix_messenger/features/rooms/domain/models/new_room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/sync_state.dart';
import 'package:matrix_messenger/features/rooms/domain/models/user_check.dart';

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

  Result<CreatedRoom> createRoomResult = const Result.ok(
    CreatedRoom(roomId: '!nova:b.c'),
  );

  Completer<void>? createRoomGate;

  final createdRooms = <NewRoom>[];

  @override
  Future<Result<CreatedRoom>> createRoom(NewRoom room) async {
    createdRooms.add(room);
    await createRoomGate?.future;
    return createRoomResult;
  }

  final userChecks = <String, UserCheck>{};

  Completer<void>? checkUserGate;

  final checkedUsers = <String>[];

  @override
  Future<UserCheck> checkUser(String userId) async {
    checkedUsers.add(userId);
    await checkUserGate?.future;
    return userChecks[userId] ?? const UserFound();
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

  Result<MessageSearchPage> searchResult = const Result.ok(
    MessageSearchPage(hits: []),
  );

  Completer<void>? searchGate;

  final searches = <(String, String?)>[];

  @override
  Future<Result<MessageSearchPage>> searchMessages(
    String term, {
    String? nextBatch,
  }) async {
    searches.add((term, nextBatch));
    await searchGate?.future;
    return searchResult;
  }

  Future<void> dispose() async {
    await roomsController.close();
    await syncStateController.close();
  }
}
