import 'package:equatable/equatable.dart';

import '../../domain/models/recovery_failure.dart';

enum SetupRecoveryStep { intro, creating, ready, failure }

final class SetupRecoveryState extends Equatable {
  const SetupRecoveryState({
    this.step = SetupRecoveryStep.intro,
    this.recoveryKey,
    this.confirmed = false,
    this.failure,
  });

  final SetupRecoveryStep step;

  final String? recoveryKey;

  final bool confirmed;

  final RecoveryFailureType? failure;

  // A chave não aparece de novo: com ela na tela, só fecha depois da confirmação.
  bool get canClose => switch (step) {
    SetupRecoveryStep.creating => false,
    SetupRecoveryStep.ready => confirmed,
    SetupRecoveryStep.intro || SetupRecoveryStep.failure => true,
  };

  @override
  List<Object?> get props => [step, recoveryKey, confirmed, failure];
}
