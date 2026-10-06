import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/recovery/data/repositories/recovery_repository_matrix.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_failure.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_status.dart';
import 'package:matrix_messenger/src/rust/api/recovery.dart' as bridge;

import '../../../../../testing/fakes/services/fake_matrix_service.dart';

void main() {
  late FakeMatrixService service;
  late RecoveryRepositoryMatrix repository;

  setUp(() {
    service = FakeMatrixService();
    repository = RecoveryRepositoryMatrix(service);
  });

  tearDown(() => service.dispose());

  test('converte o status da ponte', () async {
    final received = repository.status.first;
    service.recoveryController.add(bridge.RecoveryStatus.incomplete);

    expect(await received, RecoveryStatus.incomplete);
  });

  test('repassa a chave e devolve ok', () async {
    final result = await repository.recover('EsTx 1234');

    expect(result, isA<Ok<void>>());
    expect(service.recoverCalls, ['EsTx 1234']);
  });

  test('converte RecoveryError em RecoveryFailure', () async {
    service.recoverResult = const Result.error(
      bridge.RecoveryError(
        kind: bridge.RecoveryErrorKind.invalidKey,
        message: 'MAC',
      ),
    );

    final result = await repository.recover('errada');

    expect(
      result,
      isA<Error<void>>().having(
        (error) => (error.error as RecoveryFailure).type,
        'type',
        RecoveryFailureType.invalidKey,
      ),
    );
  });

  test('setupRecovery devolve a chave', () async {
    service.setupRecoveryResult = const Result.ok('EsTx 9999');

    final result = await repository.setupRecovery();

    expect((result as Ok<String>).value, 'EsTx 9999');
    expect(service.setupRecoveryCalls, 1);
  });

  for (final (kind, type) in [
    (bridge.RecoveryErrorKind.backupExists, RecoveryFailureType.backupExists),
    (bridge.RecoveryErrorKind.authRequired, RecoveryFailureType.authRequired),
    (bridge.RecoveryErrorKind.network, RecoveryFailureType.network),
  ]) {
    test('setupRecovery converte $kind', () async {
      service.setupRecoveryResult = Result.error(
        bridge.RecoveryError(kind: kind, message: 'x'),
      );

      final result = await repository.setupRecovery();

      expect(((result as Error<String>).error as RecoveryFailure).type, type);
    });
  }
}
