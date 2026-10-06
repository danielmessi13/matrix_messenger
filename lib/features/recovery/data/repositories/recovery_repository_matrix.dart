import '../../../../core/services/matrix_service.dart';
import '../../../../core/utils/result.dart';
import '../../../../src/rust/api/recovery.dart' as bridge;
import '../../domain/models/recovery_failure.dart';
import '../../domain/models/recovery_status.dart';
import 'recovery_repository.dart';

class RecoveryRepositoryMatrix implements RecoveryRepository {
  RecoveryRepositoryMatrix(this._service);

  final MatrixService _service;

  @override
  Stream<RecoveryStatus> get status => _service.watchRecovery().map(_toStatus);

  @override
  Future<Result<void>> recover(String recoveryKey) async {
    switch (await _service.recover(recoveryKey)) {
      case Ok():
        return const Result.ok(null);
      case Error(:final error):
        return Result.error(_toFailure(error));
    }
  }

  RecoveryStatus _toStatus(bridge.RecoveryStatus status) => switch (status) {
    bridge.RecoveryStatus.unknown => RecoveryStatus.unknown,
    bridge.RecoveryStatus.enabled => RecoveryStatus.enabled,
    bridge.RecoveryStatus.disabled => RecoveryStatus.disabled,
    bridge.RecoveryStatus.incomplete => RecoveryStatus.incomplete,
  };

  RecoveryFailure _toFailure(Exception error) => switch (error) {
    bridge.RecoveryError(:final kind, :final message) => RecoveryFailure(
      switch (kind) {
        bridge.RecoveryErrorKind.invalidKey => RecoveryFailureType.invalidKey,
        bridge.RecoveryErrorKind.network => RecoveryFailureType.network,
        bridge.RecoveryErrorKind.unknown => RecoveryFailureType.unknown,
      },
      message,
    ),
    _ => RecoveryFailure(RecoveryFailureType.unknown, '$error'),
  };
}
