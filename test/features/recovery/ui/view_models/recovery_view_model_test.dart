import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_failure.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_status.dart';
import 'package:matrix_messenger/features/recovery/ui/view_models/recovery_state.dart';
import 'package:matrix_messenger/features/recovery/ui/view_models/recovery_view_model.dart';

import '../../../../../testing/fakes/repositories/fake_recovery_repository.dart';

void main() {
  late FakeRecoveryRepository repository;

  setUp(() => repository = FakeRecoveryRepository());

  tearDown(() => repository.dispose());

  blocTest<RecoveryViewModel, RecoveryState>(
    'mostra o cartão só quando o backup está incompleto',
    build: () => RecoveryViewModel(repository)..init(),
    act: (_) async {
      repository.statusController.add(RecoveryStatus.unknown);
      await Future<void>.delayed(Duration.zero);
      repository.statusController.add(RecoveryStatus.incomplete);
    },
    expect: () => const [
      RecoveryState(),
      RecoveryState(status: RecoveryStatus.incomplete),
    ],
    verify: (viewModel) =>
        expect(viewModel.state.card, RecoveryCardKind.unlock),
  );

  blocTest<RecoveryViewModel, RecoveryState>(
    'recuperação com sucesso termina em success',
    build: () => RecoveryViewModel(repository),
    seed: () => const RecoveryState(status: RecoveryStatus.incomplete),
    act: (viewModel) => viewModel.recover('EsTx 1234'),
    expect: () => const [
      RecoveryState(
        status: RecoveryStatus.incomplete,
        submit: RecoverySubmit.running,
      ),
      RecoveryState(
        status: RecoveryStatus.incomplete,
        submit: RecoverySubmit.success,
      ),
    ],
    verify: (viewModel) {
      expect(repository.recoveredWith, ['EsTx 1234']);
      // O cartão só some quando o usuário fecha o estado de sucesso.
      expect(viewModel.state.card, RecoveryCardKind.unlock);
    },
  );

  blocTest<RecoveryViewModel, RecoveryState>(
    'resetSubmit limpa a falha anterior',
    build: () => RecoveryViewModel(repository),
    seed: () => const RecoveryState(
      status: RecoveryStatus.incomplete,
      submit: RecoverySubmit.failure,
      failure: RecoveryFailureType.invalidKey,
    ),
    act: (viewModel) => viewModel.resetSubmit(),
    expect: () => const [RecoveryState(status: RecoveryStatus.incomplete)],
  );

  blocTest<RecoveryViewModel, RecoveryState>(
    'chave inválida guarda a falha',
    build: () {
      repository.recoverResult = const Result.error(
        RecoveryFailure(RecoveryFailureType.invalidKey),
      );
      return RecoveryViewModel(repository);
    },
    seed: () => const RecoveryState(status: RecoveryStatus.incomplete),
    act: (viewModel) => viewModel.recover('errada'),
    skip: 1,
    expect: () => const [
      RecoveryState(
        status: RecoveryStatus.incomplete,
        submit: RecoverySubmit.failure,
        failure: RecoveryFailureType.invalidKey,
      ),
    ],
  );

  blocTest<RecoveryViewModel, RecoveryState>(
    'ignora chave vazia e envio repetido',
    build: () => RecoveryViewModel(repository),
    seed: () => const RecoveryState(submit: RecoverySubmit.running),
    act: (viewModel) => viewModel
      ..recover('   ')
      ..recover('EsTx'),
    expect: () => const <RecoveryState>[],
    verify: (_) => expect(repository.recoveredWith, isEmpty),
  );

  blocTest<RecoveryViewModel, RecoveryState>(
    'finish esconde o cartão',
    build: () => RecoveryViewModel(repository),
    seed: () => const RecoveryState(
      status: RecoveryStatus.incomplete,
      submit: RecoverySubmit.success,
    ),
    act: (viewModel) => viewModel.finish(),
    expect: () => const [
      RecoveryState(
        status: RecoveryStatus.incomplete,
        submit: RecoverySubmit.success,
        unlocked: true,
      ),
    ],
    verify: (viewModel) => expect(viewModel.state.card, RecoveryCardKind.none),
  );

  blocTest<RecoveryViewModel, RecoveryState>(
    'resetSubmit sai do sucesso',
    build: () => RecoveryViewModel(repository),
    seed: () => const RecoveryState(
      status: RecoveryStatus.incomplete,
      submit: RecoverySubmit.success,
    ),
    act: (viewModel) => viewModel.resetSubmit(),
    expect: () => const [RecoveryState(status: RecoveryStatus.incomplete)],
  );

  blocTest<RecoveryViewModel, RecoveryState>(
    'resetSubmit não interrompe um envio em andamento',
    build: () => RecoveryViewModel(repository),
    seed: () => const RecoveryState(submit: RecoverySubmit.running),
    act: (viewModel) => viewModel.resetSubmit(),
    expect: () => const <RecoveryState>[],
  );

  test('tipo do cartão pelo status', () {
    expect(const RecoveryState().card, RecoveryCardKind.none);
    expect(
      const RecoveryState(status: RecoveryStatus.enabled).card,
      RecoveryCardKind.none,
    );
    expect(
      const RecoveryState(status: RecoveryStatus.incomplete).card,
      RecoveryCardKind.unlock,
    );
    expect(
      const RecoveryState(
        status: RecoveryStatus.incomplete,
        unlocked: true,
      ).card,
      RecoveryCardKind.none,
    );
    expect(
      const RecoveryState(status: RecoveryStatus.disabled).card,
      RecoveryCardKind.setup,
    );
  });
}
