import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../domain/models/user_session.dart';
import 'auth_gate_state.dart';

class AuthGateViewModel extends Cubit<AuthGateState> {
  AuthGateViewModel(this._repository) : super(const AuthGateRestoring());

  final AuthRepository _repository;

  StreamSubscription<UserSession?>? _sessionSubscription;

  Future<void> init() async {
    _sessionSubscription ??= _repository.sessionChanges.listen(_onSession);
    await _restore();
  }

  Future<void> retryRestore() async {
    if (state is! AuthGateRestoreFailed) return;
    emit(const AuthGateRestoring());
    await _restore();
  }

  void skipRestore() {
    if (state is AuthGateRestoreFailed) emit(const AuthGateUnauthenticated());
  }

  Future<void> _restore() async {
    final result = await _repository.restoreSession();
    if (result case Error(:final error)) {
      log('Não foi possível restaurar a sessão', name: 'auth', error: error);
      if (!isClosed) emit(const AuthGateRestoreFailed());
    }
  }

  void _onSession(UserSession? session) {
    if (isClosed) return;
    emit(
      session == null
          ? const AuthGateUnauthenticated()
          : AuthGateAuthenticated(session),
    );
  }

  @override
  Future<void> close() async {
    await _sessionSubscription?.cancel();
    return super.close();
  }
}
