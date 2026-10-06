import 'dart:async';

import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
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
    this.lastSignOutReason,
    this.browserLoginFailure,
    this.browserLoginCompleter,
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

  final keepSignedInCalls = <bool>[];

  @override
  AuthFailureType? lastSignOutReason;

  Exception? browserLoginFailure;
  final Completer<void>? browserLoginCompleter;
  Uri authorizationUrl = Uri.parse(
    'https://account.matrix.org/authorize?state=abc',
  );
  final browserLoginCalls = <String>[];
  int cancelBrowserLoginCalls = 0;
  Completer<void>? _browserCancel;

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
    bool keepSignedIn = true,
  }) async {
    keepSignedInCalls.add(keepSignedIn);
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
  Future<Result<UserSession>> loginWithBrowser({
    required String homeserver,
    required void Function(Uri url) onAuthorizationUrl,
    bool keepSignedIn = true,
  }) async {
    keepSignedInCalls.add(keepSignedIn);
    browserLoginCalls.add(homeserver);
    final cancel = _browserCancel = Completer<void>();
    onAuthorizationUrl(authorizationUrl);
    await Future.any([
      cancel.future,
      browserLoginCompleter?.future ?? Future<void>.value(),
    ]);
    if (cancel.isCompleted) {
      return const Result.error(AuthFailure(AuthFailureType.cancelled));
    }
    if (browserLoginFailure case final failure?) return Result.error(failure);
    savedSession = loginSession;
    _setSession(loginSession);
    return Result.ok(loginSession);
  }

  @override
  Future<void> cancelBrowserLogin() async {
    cancelBrowserLoginCalls++;
    if (_browserCancel case final cancel? when !cancel.isCompleted) {
      cancel.complete();
    }
  }

  void revokeSession() {
    lastSignOutReason = AuthFailureType.sessionRevoked;
    savedSession = null;
    _setSession(null);
  }

  @override
  Future<void> dispose() => _sessionChanges.close();

  void _setSession(UserSession? session) {
    if (!_sessionChanges.isClosed) _sessionChanges.add(session);
  }
}
