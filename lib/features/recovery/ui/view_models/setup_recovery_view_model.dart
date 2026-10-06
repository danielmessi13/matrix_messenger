import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/result.dart';
import '../../data/repositories/recovery_repository.dart';
import '../../domain/models/recovery_failure.dart';
import 'setup_recovery_state.dart';

class SetupRecoveryViewModel extends Cubit<SetupRecoveryState> {
  SetupRecoveryViewModel(this._repository) : super(const SetupRecoveryState());

  final RecoveryRepository _repository;

  // Cada chamada gera uma chave nova e invalida a anterior.
  Future<void> create() async {
    if (state.step case SetupRecoveryStep.creating || SetupRecoveryStep.ready) {
      return;
    }
    emit(const SetupRecoveryState(step: SetupRecoveryStep.creating));

    final result = await _repository.setupRecovery();
    if (isClosed) return;
    switch (result) {
      case Ok(:final value):
        emit(
          SetupRecoveryState(step: SetupRecoveryStep.ready, recoveryKey: value),
        );
      case Error(:final error):
        log('Configurar recuperação falhou', name: 'recovery', error: error);
        emit(
          SetupRecoveryState(
            step: SetupRecoveryStep.failure,
            failure: error is RecoveryFailure
                ? error.type
                : RecoveryFailureType.unknown,
          ),
        );
    }
  }

  void setConfirmed(bool confirmed) {
    if (state.step != SetupRecoveryStep.ready) return;
    emit(
      SetupRecoveryState(
        step: SetupRecoveryStep.ready,
        recoveryKey: state.recoveryKey,
        confirmed: confirmed,
      ),
    );
  }
}
