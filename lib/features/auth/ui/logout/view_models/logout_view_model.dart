import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/auth_repository.dart';
import 'logout_state.dart';

class LogoutViewModel extends Cubit<LogoutState> {
  LogoutViewModel(this._repository) : super(const LogoutState());

  final AuthRepository _repository;

  Future<void> logout() async {
    if (isClosed || state.status == LogoutStatus.running) return;
    emit(const LogoutState(status: LogoutStatus.running));

    final result = await _repository.logout();
    switch (result) {
      case Ok():
        _emitIfOpen(const LogoutState());
      case Error(:final error):
        log('Logout falhou', name: 'auth', error: error);
        _emitIfOpen(const LogoutState(status: LogoutStatus.failure));
    }
  }

  void _emitIfOpen(LogoutState state) {
    if (!isClosed) emit(state);
  }
}
