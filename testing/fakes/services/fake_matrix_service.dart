import 'dart:async';
import 'dart:typed_data';

import 'package:matrix_messenger/core/services/matrix_service.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/src/rust/api/client.dart';
import 'package:matrix_messenger/src/rust/api/recovery.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart';
import 'package:matrix_messenger/src/rust/api/search.dart';
import 'package:matrix_messenger/src/rust/api/threads.dart';
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
  final keepSignedInCalls = <bool>[];
  int cancelBrowserLoginCalls = 0;
  final revokedController = StreamController<void>.broadcast();

  final roomsController = StreamController<List<RoomSummary>>.broadcast();

  final syncStatusController = StreamController<SyncStatus>.broadcast();

  final recoveryController = StreamController<RecoveryStatus>.broadcast();

  final recentThreadsController =
      StreamController<RecentThreadsSnapshot>.broadcast();

  var recentThreadsRetries = 0;

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
    bool keepSignedIn = true,
  }) async {
    keepSignedInCalls.add(keepSignedIn);
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
    bool keepSignedIn = true,
  }) async {
    keepSignedInCalls.add(keepSignedIn);
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
  Stream<RecentThreadsSnapshot> watchRecentThreads() =>
      recentThreadsController.stream;

  @override
  Future<void> retryRecentThreads() async => recentThreadsRetries++;

  @override
  Future<Result<void>> recover(String recoveryKey) async {
    recoverCalls.add(recoveryKey);
    return recoverResult;
  }

  @override
  Future<Result<RoomTimeline>> openTimeline(String roomId) async =>
      openTimelineResult;

  Result<Uint8List> Function(String media, bool thumbnail) loadMediaResult = (
    media,
    _,
  ) => Result.ok(Uint8List.fromList(media.codeUnits));

  final loadMediaCalls = <(String, bool)>[];

  @override
  Future<Result<Uint8List>> loadMedia(
    String media, {
    required bool thumbnail,
  }) async {
    loadMediaCalls.add((media, thumbnail));
    return loadMediaResult(media, thumbnail);
  }

  Result<void> inviteResult = const Result.ok(null);

  final accepted = <String>[];

  final declined = <String>[];

  @override
  Future<Result<void>> acceptInvite(String roomId) async {
    accepted.add(roomId);
    return inviteResult;
  }

  @override
  Future<Result<void>> declineInvite(String roomId) async {
    declined.add(roomId);
    return inviteResult;
  }

  Result<CreatedRoom> createRoomResult = const Result.ok(
    CreatedRoom(roomId: '!nova:b.c', failedInvites: []),
  );

  final createdRooms = <NewRoom>[];

  @override
  Future<Result<CreatedRoom>> createRoom(NewRoom room) async {
    createdRooms.add(room);
    return createRoomResult;
  }

  Result<UserCheck> checkUserResult = const Result.ok(
    UserCheck(status: UserCheckStatus.found, displayName: 'Ana'),
  );

  @override
  Future<Result<UserCheck>> checkUser(String userId) async => checkUserResult;

  Result<String?> roomLinkResult = const Result.ok(
    'https://matrix.to/#/!a:b.c?via=b.c',
  );

  @override
  Future<Result<String?>> roomLink(String roomId) async => roomLinkResult;

  Result<String> joinRoomResult = const Result.ok('!entrou:b.c');

  final joinedTargets = <String>[];

  @override
  Future<Result<String>> joinRoom(String target) async {
    joinedTargets.add(target);
    return joinRoomResult;
  }

  Result<MessageSearchPage> searchMessagesResult = const Result.ok(
    MessageSearchPage(hits: []),
  );

  final searches = <(String, String?)>[];

  @override
  Future<Result<MessageSearchPage>> searchMessages(
    String term, {
    String? nextBatch,
  }) async {
    searches.add((term, nextBatch));
    return searchMessagesResult;
  }

  Future<void> dispose() async {
    await revokedController.close();
    await roomsController.close();
    await syncStatusController.close();
    await recoveryController.close();
    await recentThreadsController.close();
  }
}
