import 'dart:async';

import '../../../../core/services/local_storage_exception.dart';
import '../../../../core/services/matrix_service.dart';
import '../../../../core/utils/result.dart';
import '../../../../src/rust/api/auth.dart';
import '../../domain/models/auth_failure.dart';
import '../../domain/models/user_session.dart';
import 'auth_repository.dart';

class AuthRepositoryMatrix implements AuthRepository {
  AuthRepositoryMatrix(this._service) {
    _revokedSubscription = _service.sessionRevoked.listen((_) {
      _lastSignOutReason = AuthFailureType.sessionRevoked;
      _setSession(null);
    });
  }

  final MatrixService _service;

  final _sessionChanges = StreamController<UserSession?>.broadcast();

  late final StreamSubscription<void> _revokedSubscription;

  AuthFailureType? _lastSignOutReason;

  @override
  AuthFailureType? get lastSignOutReason => _lastSignOutReason;

  @override
  Stream<UserSession?> get sessionChanges => _sessionChanges.stream;

  @override
  Future<Result<UserSession?>> restoreSession() async {
    switch (await _service.restoreSession()) {
      case Ok(:final value):
        final session = value == null ? null : _toSession(value);
        _setSession(session);
        return Result.ok(session);
      case Error(:final error):
        return Result.error(_toFailure(error));
    }
  }

  @override
  Future<Result<UserSession>> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    _lastSignOutReason = null;
    return _adoptLogin(
      await _service.login(
        homeserver: homeserver,
        username: username,
        password: password,
      ),
    );
  }

  @override
  Future<Result<UserSession>> loginWithBrowser({
    required String homeserver,
    required void Function(Uri url) onAuthorizationUrl,
  }) async {
    _lastSignOutReason = null;
    return _adoptLogin(
      await _service.loginWithBrowser(
        homeserver: homeserver,
        onAuthorizationUrl: onAuthorizationUrl,
      ),
    );
  }

  @override
  Future<void> cancelBrowserLogin() => _service.cancelBrowserLogin();

  Result<UserSession> _adoptLogin(Result<MatrixClient> result) {
    switch (result) {
      case Ok(:final value):
        final session = _toSession(value);
        _setSession(session);
        return Result.ok(session);
      case Error(:final error):
        return Result.error(_toFailure(error));
    }
  }

  @override
  Future<Result<void>> logout() async {
    _lastSignOutReason = null;
    switch (await _service.logout()) {
      case Ok():
        _setSession(null);
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(_toFailure(error));
    }
  }

  @override
  Future<void> dispose() async {
    await _revokedSubscription.cancel();
    await _sessionChanges.close();
  }

  void _setSession(UserSession? session) {
    // Uma operação pode terminar depois do dispose.
    if (!_sessionChanges.isClosed) _sessionChanges.add(session);
  }

  UserSession _toSession(MatrixClient client) => UserSession(
    userId: client.userId,
    deviceId: client.deviceId,
    sessionSaved: client.sessionSaved,
  );

  AuthFailure _toFailure(Exception error) => switch (error) {
    AuthError(:final kind, :final message) => AuthFailure(
      _toFailureType(kind),
      message,
    ),
    LocalStorageException(:final details) => AuthFailure(
      AuthFailureType.storage,
      details,
    ),
    _ => AuthFailure(AuthFailureType.unknown, '$error'),
  };

  // Mantém o tipo gerado pela ponte fora do domínio; o switch quebra se o Rust ganhar um kind novo.
  AuthFailureType _toFailureType(AuthErrorKind kind) => switch (kind) {
    AuthErrorKind.invalidHomeserver => AuthFailureType.invalidHomeserver,
    AuthErrorKind.homeserverUnreachable =>
      AuthFailureType.homeserverUnreachable,
    AuthErrorKind.invalidCredentials => AuthFailureType.invalidCredentials,
    AuthErrorKind.userDeactivated => AuthFailureType.userDeactivated,
    AuthErrorKind.rateLimited => AuthFailureType.rateLimited,
    AuthErrorKind.storage => AuthFailureType.storage,
    AuthErrorKind.oidcNotSupported => AuthFailureType.oidcNotSupported,
    AuthErrorKind.authorizationDenied => AuthFailureType.authorizationDenied,
    AuthErrorKind.timedOut => AuthFailureType.timedOut,
    AuthErrorKind.cancelled => AuthFailureType.cancelled,
    AuthErrorKind.unknown => AuthFailureType.unknown,
  };
}
