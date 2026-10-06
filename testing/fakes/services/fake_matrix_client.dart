import 'dart:async';
import 'dart:typed_data';

import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/src/rust/api/client.dart';
import 'package:matrix_messenger/src/rust/api/recovery.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart';
import 'package:matrix_messenger/src/rust/api/search.dart';
import 'package:matrix_messenger/src/rust/api/timeline.dart';

import 'fake_room_timeline.dart';

class FakeMatrixClient implements MatrixClient {
  FakeMatrixClient({
    required this.userId,
    required this.deviceId,
    this.sessionSaved = true,
  });

  FakeMatrixClient.of(UserSession session)
    : this(
        userId: session.userId,
        deviceId: session.deviceId,
        sessionSaved: session.sessionSaved,
      );

  @override
  final String userId;

  @override
  final String deviceId;

  @override
  final bool sessionSaved;

  @override
  bool isDisposed = false;

  @override
  Future<void> logout() async {}

  final sessionEventsController = StreamController<SessionEvent>.broadcast();

  @override
  Stream<SessionEvent> sessionEvents() => sessionEventsController.stream;

  final roomsController = StreamController<List<RoomSummary>>.broadcast();

  final syncStatusController = StreamController<SyncStatus>.broadcast();

  @override
  Stream<List<RoomSummary>> watchRooms() => roomsController.stream;

  @override
  Stream<SyncStatus> watchSyncStatus() => syncStatusController.stream;

  final recoveryController = StreamController<RecoveryStatus>.broadcast();

  @override
  Stream<RecoveryStatus> watchRecovery() => recoveryController.stream;

  Object? recoverError;

  final recoveredWith = <String>[];

  @override
  Future<void> recover({required String recoveryKey}) async {
    recoveredWith.add(recoveryKey);
    if (recoverError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  RoomTimeline? openTimelineResult;

  Object? openTimelineError;

  final openedRooms = <String>[];

  @override
  Future<RoomTimeline> openTimeline({required String roomId}) async {
    openedRooms.add(roomId);
    if (openTimelineError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return openTimelineResult ?? FakeRoomTimeline();
  }

  Object? inviteError;

  final accepted = <String>[];

  final declined = <String>[];

  @override
  Future<void> acceptInvite({required String roomId}) async {
    accepted.add(roomId);
    if (inviteError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  @override
  Future<void> declineInvite({required String roomId}) async {
    declined.add(roomId);
    if (inviteError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }

  CreatedRoom createdRoom = const CreatedRoom(
    roomId: '!nova:b.c',
    failedInvites: [],
  );

  final createdRooms = <NewRoom>[];

  @override
  Future<CreatedRoom> createRoom({required NewRoom room}) async {
    createdRooms.add(room);
    return createdRoom;
  }

  String? roomLinkValue = 'https://matrix.to/#/!a:b.c?via=b.c';

  @override
  Future<String?> roomLink({required String roomId}) async => roomLinkValue;

  final joinedTargets = <String>[];

  @override
  Future<String> joinRoom({required String target}) async {
    joinedTargets.add(target);
    return '!entrou:b.c';
  }

  UserCheck userCheck = const UserCheck(
    status: UserCheckStatus.found,
    displayName: null,
  );

  @override
  Future<UserCheck> checkUser({required String userId}) async => userCheck;

  MessageSearchPage searchPage = const MessageSearchPage(hits: []);

  @override
  Future<MessageSearchPage> searchMessages({
    required String term,
    String? nextBatch,
  }) async => searchPage;

  final loadedMedia = <(String, bool)>[];

  Object? loadMediaError;

  @override
  Future<Uint8List> loadMedia({
    required String media,
    required bool thumbnail,
  }) async {
    loadedMedia.add((media, thumbnail));
    if (loadMediaError case final error?) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return Uint8List.fromList(media.codeUnits);
  }

  @override
  void dispose() {
    isDisposed = true;
    sessionEventsController.close();
    roomsController.close();
    syncStatusController.close();
    recoveryController.close();
  }
}
