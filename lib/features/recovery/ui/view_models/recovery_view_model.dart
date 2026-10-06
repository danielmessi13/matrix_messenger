import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/result.dart';
import '../../data/repositories/recovery_repository.dart';
import '../../domain/models/recovery_failure.dart';
import '../../domain/models/recovery_status.dart';
import 'recovery_state.dart';

class RecoveryViewModel extends Cubit<RecoveryState> {
  RecoveryViewModel(this._repository) : super(const RecoveryState());

  final RecoveryRepository _repository;

  StreamSubscription<RecoveryStatus>? _status;

  void init() {
    _status ??= _repository.status.listen(
      (status) => emit(state.copyWith(status: status)),
      onError: (Object error) =>
          log('Status da recuperação falhou', name: 'recovery', error: error),
    );
  }

  // O erro é de uma tentativa; um diálogo novo começa limpo.
  void resetSubmit() {
    if (state.submit != RecoverySubmit.failure) return;
    emit(state.copyWith(submit: RecoverySubmit.idle, failure: () => null));
  }

  void dismiss() => emit(state.copyWith(dismissed: true));

  Future<void> recover(String recoveryKey) async {
    if (recoveryKey.trim().isEmpty || state.submit == RecoverySubmit.running) {
      return;
    }
    emit(state.copyWith(submit: RecoverySubmit.running, failure: () => null));

    final result = await _repository.recover(recoveryKey);
    if (isClosed) return;
    switch (result) {
      case Ok():
        emit(state.copyWith(submit: RecoverySubmit.success));
      case Error(:final error):
        log('Recuperação falhou', name: 'recovery', error: error);
        final type = error is RecoveryFailure
            ? error.type
            : RecoveryFailureType.unknown;
        emit(
          state.copyWith(submit: RecoverySubmit.failure, failure: () => type),
        );
    }
  }

  @override
  Future<void> close() async {
    await _status?.cancel();
    return super.close();
  }
}
