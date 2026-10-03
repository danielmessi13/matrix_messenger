import 'dart:async';

import '../../../../core/services/local_storage_exception.dart';
import '../../../../core/services/matrix_service.dart';
import '../../../../core/utils/result.dart';
import '../../../../src/rust/api/auth.dart';
import '../../domain/models/auth_failure.dart';
import '../../domain/models/user_session.dart';
import 'auth_repository.dart';

class AuthRepositoryMatrix implements AuthRepository {
  AuthRepositoryMatrix(this._service);

  final MatrixService _service;

  final _sessionChanges = StreamController<UserSession?>.broadcast();

  // TODO: emitir null quando o token for revogado em outro cliente (`SessionChange::UnknownToken`).
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
    final result = await _service.login(
      homeserver: homeserver,
      username: username,
      password: password,
    );
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
    switch (await _service.logout()) {
      case Ok():
        _setSession(null);
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(_toFailure(error));
    }
  }

  @override
  Future<void> dispose() => _sessionChanges.close();

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

  AuthFailureType _toFailureType(AuthErrorKind kind) => switch (kind) {
    AuthErrorKind.invalidHomeserver => AuthFailureType.invalidHomeserver,
    AuthErrorKind.homeserverUnreachable =>
      AuthFailureType.homeserverUnreachable,
    AuthErrorKind.invalidCredentials => AuthFailureType.invalidCredentials,
    AuthErrorKind.userDeactivated => AuthFailureType.userDeactivated,
    AuthErrorKind.rateLimited => AuthFailureType.rateLimited,
    AuthErrorKind.storage => AuthFailureType.storage,
    AuthErrorKind.unknown => AuthFailureType.unknown,
  };
}
