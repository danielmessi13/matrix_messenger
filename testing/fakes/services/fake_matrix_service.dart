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

  final loginCalls =
      <({String homeserver, String username, String password})>[];

  @override
  MatrixClient? get client => null;

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
}
