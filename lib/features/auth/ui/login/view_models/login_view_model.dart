import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../domain/models/auth_failure.dart';
import 'login_state.dart';

class LoginViewModel extends Cubit<LoginState> {
  LoginViewModel(this._repository) : super(const LoginState());

  final AuthRepository _repository;

  Future<void> login({
    required String homeserver,
    required String username,
    required String password,
  }) async {
    if (state.status == LoginStatus.running) return;
    emit(const LoginState(status: LoginStatus.running));

    final result = await _repository.login(
      homeserver: homeserver,
      username: username,
      password: password,
    );
    switch (result) {
      case Ok():
        _emitIfOpen(const LoginState());
      case Error(:final error):
        log('Login falhou', name: 'auth', error: error);
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
