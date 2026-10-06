import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_failure.dart';
import 'package:matrix_messenger/features/recovery/ui/view_models/setup_recovery_state.dart';
import 'package:matrix_messenger/features/recovery/ui/view_models/setup_recovery_view_model.dart';

import '../../../../../testing/fakes/repositories/fake_recovery_repository.dart';

void main() {
  late FakeRecoveryRepository repository;

  setUp(() => repository = FakeRecoveryRepository());

  tearDown(() => repository.dispose());

  blocTest<SetupRecoveryViewModel, SetupRecoveryState>(
    'create vai de creating para ready com a chave',
    build: () => SetupRecoveryViewModel(repository),
    act: (viewModel) => viewModel.create(),
    expect: () => const [
      SetupRecoveryState(step: SetupRecoveryStep.creating),
      SetupRecoveryState(
        step: SetupRecoveryStep.ready,
        recoveryKey: kFakeRecoveryKey,
      ),
    ],
  );

  blocTest<SetupRecoveryViewModel, SetupRecoveryState>(
    'falha guarda o tipo',
    build: () {
      repository.setupResult = const Result.error(
        RecoveryFailure(RecoveryFailureType.backupExists),
      );
      return SetupRecoveryViewModel(repository);
    },
    act: (viewModel) => viewModel.create(),
    expect: () => const [
      SetupRecoveryState(step: SetupRecoveryStep.creating),
      SetupRecoveryState(
        step: SetupRecoveryStep.failure,
        failure: RecoveryFailureType.backupExists,
      ),
    ],
  );

  blocTest<SetupRecoveryViewModel, SetupRecoveryState>(
    'exceção desconhecida vira unknown',
    build: () {
      repository.setupResult = Result.error(Exception('boom'));
      return SetupRecoveryViewModel(repository);
    },
    act: (viewModel) => viewModel.create(),
    skip: 1,
    expect: () => const [
      SetupRecoveryState(
        step: SetupRecoveryStep.failure,
        failure: RecoveryFailureType.unknown,
      ),
    ],
  );

  blocTest<SetupRecoveryViewModel, SetupRecoveryState>(
    'tentar de novo a partir da falha chama o repositório outra vez',
    build: () => SetupRecoveryViewModel(repository),
    seed: () => const SetupRecoveryState(
      step: SetupRecoveryStep.failure,
      failure: RecoveryFailureType.network,
    ),
    act: (viewModel) => viewModel.create(),
    expect: () => const [
      SetupRecoveryState(step: SetupRecoveryStep.creating),
      SetupRecoveryState(
        step: SetupRecoveryStep.ready,
        recoveryKey: kFakeRecoveryKey,
      ),
    ],
    verify: (_) => expect(repository.setupCalls, 1),
  );

  test('create em andamento não chama de novo', () async {
    repository.setupGate = Completer<void>();
    final viewModel = SetupRecoveryViewModel(repository);
    addTearDown(viewModel.close);

    final first = viewModel.create();
    await viewModel.create();
    repository.setupGate!.complete();
    await first;

    expect(repository.setupCalls, 1);
  });

  blocTest<SetupRecoveryViewModel, SetupRecoveryState>(
    'create com a chave pronta não gera outra',
    build: () => SetupRecoveryViewModel(repository),
    seed: () => const SetupRecoveryState(
      step: SetupRecoveryStep.ready,
      recoveryKey: kFakeRecoveryKey,
    ),
    act: (viewModel) => viewModel.create(),
    expect: () => const <SetupRecoveryState>[],
    verify: (_) => expect(repository.setupCalls, 0),
  );

  blocTest<SetupRecoveryViewModel, SetupRecoveryState>(
    'setConfirmed só vale com a chave pronta',
    build: () => SetupRecoveryViewModel(repository),
    seed: () => const SetupRecoveryState(
      step: SetupRecoveryStep.ready,
      recoveryKey: kFakeRecoveryKey,
    ),
    act: (viewModel) => viewModel.setConfirmed(true),
    expect: () => const [
      SetupRecoveryState(
        step: SetupRecoveryStep.ready,
        recoveryKey: kFakeRecoveryKey,
        confirmed: true,
      ),
    ],
  );

  blocTest<SetupRecoveryViewModel, SetupRecoveryState>(
    'setConfirmed fora de ready é ignorado',
    build: () => SetupRecoveryViewModel(repository),
    act: (viewModel) => viewModel.setConfirmed(true),
    expect: () => const <SetupRecoveryState>[],
  );

  test('canClose: bloqueia criando e chave pronta sem confirmar', () {
    expect(const SetupRecoveryState().canClose, isTrue);
    expect(
      const SetupRecoveryState(step: SetupRecoveryStep.creating).canClose,
      isFalse,
    );
    expect(
      const SetupRecoveryState(step: SetupRecoveryStep.ready).canClose,
      isFalse,
    );
    expect(
      const SetupRecoveryState(
        step: SetupRecoveryStep.ready,
        confirmed: true,
      ).canClose,
      isTrue,
    );
    expect(
      const SetupRecoveryState(step: SetupRecoveryStep.failure).canClose,
      isTrue,
    );
  });
}
