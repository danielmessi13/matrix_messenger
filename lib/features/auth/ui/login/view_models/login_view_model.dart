import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/services/browser_launcher.dart';
import '../../../../../core/utils/result.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../domain/models/auth_failure.dart';
import '../../../domain/models/user_session.dart';
import 'login_state.dart';

class LoginViewModel extends Cubit<LoginState> {
  LoginViewModel(this._repository, this._browser)
    : super(_initialState(_repository));

  final AuthRepository _repository;

  final BrowserLauncher _browser;

  bool _browserUnavailable = false;

  static LoginState _initialState(AuthRepository repository) =>
      switch (repository.lastSignOutReason) {
        null => const LoginState(),
        final reason => LoginState(
          status: LoginStatus.failure,
          failureType: reason,
        ),
      };

  bool get _busy =>
      state.status == LoginStatus.running ||
      state.status == LoginStatus.awaitingBrowser;

  Future<void> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    if (_busy) return;
    emit(const LoginState(status: LoginStatus.running));

    final result = await _repository.login(
      homeserver: homeserver,
      username: username,
      password: password,
    );
    _finish(result, 'Login falhou');
  }

  Future<void> loginWithBrowser({required String homeserver}) async {
    if (_busy) return;
    _browserUnavailable = false;
    emit(const LoginState(status: LoginStatus.running));

    final result = await _repository.loginWithBrowser(
      homeserver: homeserver,
      onAuthorizationUrl: (url) {
        _emitIfOpen(
          LoginState(
            status: LoginStatus.awaitingBrowser,
            authorizationUrl: url,
          ),
        );
        _openBrowser(url);
      },
    );
    if (_browserUnavailable) {
      _emitIfOpen(
        const LoginState(
          status: LoginStatus.failure,
          failureType: AuthFailureType.browserUnavailable,
        ),
      );
      return;
    }
    _finish(result, 'Login pelo navegador falhou');
  }

  Future<void> reopenBrowser() async {
    if (state case LoginState(
      status: LoginStatus.awaitingBrowser,
      authorizationUrl: final url?,
    )) {
      await _openBrowser(url);
    }
  }

  Future<void> cancelBrowserLogin() async {
    if (state.status != LoginStatus.awaitingBrowser) return;
    await _repository.cancelBrowserLogin();
  }

  Future<void> _openBrowser(Uri url) async {
    if (await _tryOpen(url)) return;
    _browserUnavailable = true;
    await _repository.cancelBrowserLogin();
  }

  Future<bool> _tryOpen(Uri url) async {
    try {
      return await _browser.open(url);
    } catch (error, stackTrace) {
      log(
        'Navegador não abriu',
        name: 'auth',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  void _finish(Result<UserSession> result, String failureLog) {
    switch (result) {
      case Ok():
      case Error(error: AuthFailure(type: AuthFailureType.cancelled)):
        _emitIfOpen(const LoginState());
      case Error(:final error):
        log(failureLog, name: 'auth', error: error);
        _emitIfOpen(
          LoginState(
            status: LoginStatus.failure,
            failureType: error is AuthFailure
                ? error.type
                : AuthFailureType.unknown,
          ),
        );
    }
  }

  void _emitIfOpen(LoginState state) {
    if (!isClosed) emit(state);
  }
}
