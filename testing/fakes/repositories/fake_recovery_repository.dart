import 'dart:async';

import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/recovery/data/repositories/recovery_repository.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_status.dart';

class FakeRecoveryRepository implements RecoveryRepository {
  final statusController = StreamController<RecoveryStatus>.broadcast();

  Result<void> recoverResult = const Result.ok(null);

  final recoveredWith = <String>[];

  @override
  Stream<RecoveryStatus> get status => statusController.stream;

  @override
  Future<Result<void>> recover(String recoveryKey) async {
    recoveredWith.add(recoveryKey);
    return recoverResult;
  }

  Future<void> dispose() => statusController.close();
}
