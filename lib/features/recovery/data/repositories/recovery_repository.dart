import '../../../../core/utils/result.dart';
import '../../domain/models/recovery_status.dart';

abstract interface class RecoveryRepository {
  Stream<RecoveryStatus> get status;

  Future<Result<void>> recover(String recoveryKey);

  Future<Result<String>> setupRecovery();
}
