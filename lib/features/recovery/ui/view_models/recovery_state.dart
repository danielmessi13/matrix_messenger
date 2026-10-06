import 'package:equatable/equatable.dart';

import '../../domain/models/recovery_failure.dart';
import '../../domain/models/recovery_status.dart';

enum RecoveryCardKind { none, unlock, setup }

enum RecoverySubmit { idle, running, success, failure }

final class RecoveryState extends Equatable {
  const RecoveryState({
    this.status = RecoveryStatus.unknown,
    this.unlocked = false,
    this.submit = RecoverySubmit.idle,
    this.failure,
  });

  final RecoveryStatus status;

  // Separado de `success`: o cartão só some quando o estado de sucesso é fechado.
  final bool unlocked;

  final RecoverySubmit submit;

  final RecoveryFailureType? failure;

  RecoveryCardKind get card => switch (status) {
    RecoveryStatus.incomplete when !unlocked => RecoveryCardKind.unlock,
    RecoveryStatus.disabled => RecoveryCardKind.setup,
    _ => RecoveryCardKind.none,
  };

  RecoveryState copyWith({
    RecoveryStatus? status,
    bool? unlocked,
    RecoverySubmit? submit,
    RecoveryFailureType? Function()? failure,
  }) => RecoveryState(
    status: status ?? this.status,
    unlocked: unlocked ?? this.unlocked,
    submit: submit ?? this.submit,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [status, unlocked, submit, failure];
}
