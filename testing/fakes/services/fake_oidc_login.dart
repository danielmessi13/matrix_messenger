import 'dart:async';

import 'package:matrix_messenger/src/rust/api/auth.dart';
import 'package:matrix_messenger/src/rust/api/oidc.dart';

class FakeOidcLogin implements OidcLogin {
  FakeOidcLogin({
    this.authorizationUrl = 'https://account.matrix.org/authorize?state=abc',
  });

  @override
  final String authorizationUrl;

  final _result = Completer<MatrixClient>();

  int cancelCalls = 0;

  void finish(MatrixClient client) => _result.complete(client);

  @override
  Future<MatrixClient> complete() => _result.future;

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (!_result.isCompleted) {
      _result.completeError(
        const AuthError(kind: AuthErrorKind.cancelled, message: 'cancelado'),
      );
    }
  }

  @override
  bool isDisposed = false;

  @override
  void dispose() => isDisposed = true;
}
