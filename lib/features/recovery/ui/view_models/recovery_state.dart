import 'package:equatable/equatable.dart';

import '../../domain/models/recovery_failure.dart';
import '../../domain/models/recovery_status.dart';

enum RecoverySubmit { idle, running, success, failure }

final class RecoveryState extends Equatable {
  const RecoveryState({
    this.status = RecoveryStatus.unknown,
    this.dismissed = false,
    this.submit = RecoverySubmit.idle,
    this.failure,
  });

  final RecoveryStatus status;

  final bool dismissed;

  final RecoverySubmit submit;

  final RecoveryFailureType? failure;

  bool get showBanner =>
      status == RecoveryStatus.incomplete &&
      !dismissed &&
      submit != RecoverySubmit.success;

  RecoveryState copyWith({
    RecoveryStatus? status,
    bool? dismissed,
    RecoverySubmit? submit,
    RecoveryFailureType? Function()? failure,
  }) => RecoveryState(
    status: status ?? this.status,
    dismissed: dismissed ?? this.dismissed,
    submit: submit ?? this.submit,
    failure: failure != null ? failure() : this.failure,
  );

  @override
  List<Object?> get props => [status, dismissed, submit, failure];
}
