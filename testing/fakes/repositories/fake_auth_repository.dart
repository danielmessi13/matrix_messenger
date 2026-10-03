import 'dart:async';

import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';
import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';

import '../../models/user_session.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.savedSession,
    this.restoreFailure,
    this.loginFailure,
    this.logoutFailure,
    this.restoreCompleter,
    this.loginCompleter,
    this.logoutCompleter,
    this.loginSession = kUserSession,
  });

  UserSession? savedSession;

  Exception? restoreFailure;
  final Exception? loginFailure;
  Exception? logoutFailure;

  final Completer<void>? restoreCompleter;
  final Completer<void>? loginCompleter;
  final Completer<void>? logoutCompleter;

  final UserSession loginSession;

  final loginCalls =
      <({String homeserver, String username, String password})>[];

  int logoutCalls = 0;

  final _sessionChanges = StreamController<UserSession?>.broadcast();

  @override
  Stream<UserSession?> get sessionChanges => _sessionChanges.stream;

  bool get hasSessionListeners => _sessionChanges.hasListener;

  @override
  Future<Result<UserSession?>> restoreSession() async {
    await restoreCompleter?.future;
    if (restoreFailure case final failure?) return Result.error(failure);
    _setSession(savedSession);
    return Result.ok(savedSession);
  }

  @override
  Future<Result<UserSession>> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    loginCalls.add((
      homeserver: homeserver,
      username: username,
      password: password,
    ));
    await loginCompleter?.future;
    if (loginFailure case final failure?) return Result.error(failure);
    savedSession = loginSession;
    _setSession(loginSession);
    return Result.ok(loginSession);
  }

  @override
  Future<Result<void>> logout() async {
    logoutCalls++;
    await logoutCompleter?.future;
    if (logoutFailure case final failure?) return Result.error(failure);
    savedSession = null;
    _setSession(null);
    return const Result.ok(null);
  }

  @override
  Future<void> dispose() => _sessionChanges.close();

  void _setSession(UserSession? session) {
    if (!_sessionChanges.isClosed) _sessionChanges.add(session);
  }
}
