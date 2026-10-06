import 'dart:async';

import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/recovery/data/repositories/recovery_repository.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_status.dart';

const kFakeRecoveryKey =
    'EsTx 1234 5678 9abc defg hijk mnop qrst uvwx yzAB CDEF GHJK';

class FakeRecoveryRepository implements RecoveryRepository {
  final statusController = StreamController<RecoveryStatus>.broadcast();

  Result<void> recoverResult = const Result.ok(null);

  final recoveredWith = <String>[];

  @override
  Stream<RecoveryStatus> get status => statusController.stream;

  // Segura o recover() para o teste ver o estado "descriptografando".
  Completer<void>? gate;

  @override
  Future<Result<void>> recover(String recoveryKey) async {
    recoveredWith.add(recoveryKey);
    await gate?.future;
    return recoverResult;
  }

  Result<String> setupResult = const Result.ok(kFakeRecoveryKey);

  int setupCalls = 0;

  // Segura o setupRecovery() para o teste ver o estado "criando".
  Completer<void>? setupGate;

  @override
  Future<Result<String>> setupRecovery() async {
    setupCalls++;
    await setupGate?.future;
    return setupResult;
  }

  Future<void> dispose() => statusController.close();
}
