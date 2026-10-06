import 'dart:async';

import 'package:matrix_messenger/core/services/matrix_service.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/src/rust/api/auth.dart';
import 'package:matrix_messenger/src/rust/api/recovery.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart';
import 'package:matrix_messenger/src/rust/api/timeline.dart';

import '../../models/user_session.dart';
import 'fake_matrix_client.dart';
import 'fake_room_timeline.dart';

class FakeMatrixService implements MatrixService {
  Result<MatrixClient?> restoreResult = const Result.ok(null);
  Result<MatrixClient> loginResult = Result.ok(
    FakeMatrixClient.of(kUserSession),
  );
  Result<void> logoutResult = const Result.ok(null);
  Result<MatrixClient> loginWithBrowserResult = Result.ok(
    FakeMatrixClient.of(kUserSession),
  );
  Uri authorizationUrl = Uri.parse(
    'https://account.matrix.org/authorize?state=abc',
  );
  final loginWithBrowserCalls = <String>[];
  int cancelBrowserLoginCalls = 0;
  final revokedController = StreamController<void>.broadcast();

  final roomsController = StreamController<List<RoomSummary>>.broadcast();

  final syncStatusController = StreamController<SyncStatus>.broadcast();

  final recoveryController = StreamController<RecoveryStatus>.broadcast();

  Result<void> recoverResult = const Result.ok(null);

  final recoverCalls = <String>[];

  Result<RoomTimeline> openTimelineResult = Result.ok(FakeRoomTimeline());

  final loginCalls =
      <({String homeserver, String username, String password})>[];

  @override
  Future<Result<MatrixClient?>> restoreSession() async => restoreResult;

  @override
  Future<Result<MatrixClient>> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    loginCalls.add((
      homeserver: homeserver,
      username: username,
      password: password,
    ));
    return loginResult;
  }

  @override
  Future<Result<void>> logout() async => logoutResult;

  @override
  Stream<void> get sessionRevoked => revokedController.stream;

  @override
  Future<Result<MatrixClient>> loginWithBrowser({
    required String homeserver,
    required void Function(Uri url) onAuthorizationUrl,
  }) async {
    loginWithBrowserCalls.add(homeserver);
    onAuthorizationUrl(authorizationUrl);
    return loginWithBrowserResult;
  }

  @override
  Future<void> cancelBrowserLogin() async => cancelBrowserLoginCalls++;

  @override
  Stream<List<RoomSummary>> watchRooms() => roomsController.stream;

  @override
  Stream<SyncStatus> watchSyncStatus() => syncStatusController.stream;

  @override
  Stream<RecoveryStatus> watchRecovery() => recoveryController.stream;

  @override
  Future<Result<void>> recover(String recoveryKey) async {
    recoverCalls.add(recoveryKey);
    return recoverResult;
  }

  @override
  Future<Result<RoomTimeline>> openTimeline(String roomId) async =>
      openTimelineResult;

  Future<void> dispose() async {
    await revokedController.close();
    await roomsController.close();
    await syncStatusController.close();
    await recoveryController.close();
  }
}
