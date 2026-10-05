import 'dart:async';

import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/src/rust/api/auth.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart';

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

  @override
  void dispose() {
    isDisposed = true;
    sessionEventsController.close();
    roomsController.close();
    syncStatusController.close();
  }
}
