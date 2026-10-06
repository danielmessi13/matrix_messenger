import 'package:matrix_messenger/core/services/matrix_bridge.dart';
import 'package:matrix_messenger/src/rust/api/client.dart';
import 'package:matrix_messenger/src/rust/api/oidc.dart';

import '../../models/user_session.dart';
import 'fake_matrix_client.dart';
import 'fake_oidc_login.dart';

class FakeMatrixBridge implements MatrixBridge {
  MatrixClient? restoredClient;
  MatrixClient loginClient = FakeMatrixClient.of(kUserSession);
  FakeOidcLogin browserLogin = FakeOidcLogin();
  final keepSignedInCalls = <bool>[];

  @override
  Future<MatrixClient?> restoreSession({required String dataDir}) async =>
      restoredClient;

  @override
  Future<MatrixClient> login({
    required String homeserver,
    required String username,
    required String password,
    required String dataDir,
    required bool keepSignedIn,
  }) async {
    keepSignedInCalls.add(keepSignedIn);
    return loginClient;
  }

  @override
  Future<OidcLogin> startBrowserLogin({
    required String homeserver,
    required String dataDir,
    required bool keepSignedIn,
  }) async {
    keepSignedInCalls.add(keepSignedIn);
    return browserLogin;
  }
}
