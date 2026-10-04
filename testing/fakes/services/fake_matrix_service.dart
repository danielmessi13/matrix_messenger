import 'dart:async';

import 'package:matrix_messenger/core/services/matrix_service.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/src/rust/api/auth.dart';

import '../../models/user_session.dart';
import 'fake_matrix_client.dart';

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
}
