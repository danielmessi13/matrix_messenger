import 'dart:async';

import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/src/rust/api/client.dart';
import 'package:matrix_messenger/src/rust/api/notifications.dart';
import 'package:matrix_messenger/src/rust/api/recovery.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart';
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

  final notificationsController =
      StreamController<RoomNotification>.broadcast();

  @override
  Stream<RoomNotification> watchNotifications() =>
      notificationsController.stream;

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

  @override
  void dispose() {
    isDisposed = true;
    sessionEventsController.close();
    roomsController.close();
    syncStatusController.close();
    recoveryController.close();
    notificationsController.close();
  }
}
