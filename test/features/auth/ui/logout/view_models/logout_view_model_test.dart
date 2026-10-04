import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
import 'package:matrix_messenger/features/auth/ui/logout/view_models/logout_state.dart';
import 'package:matrix_messenger/features/auth/ui/logout/view_models/logout_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../../../../testing/models/user_session.dart';

void main() {
  late FakeAuthRepository repository;

  tearDown(() => repository.dispose());

  test('estado inicial é idle', () {
    repository = FakeAuthRepository();
    expect(LogoutViewModel(repository).state, const LogoutState());
  });

  blocTest<LogoutViewModel, LogoutState>(
    'com sucesso emite running e volta para idle',
    build: () => LogoutViewModel(
      repository = FakeAuthRepository(savedSession: kUserSession),
    ),
    act: (viewModel) => viewModel.logout(),
    expect: () => const [
      LogoutState(status: LogoutStatus.running),
      LogoutState(),
    ],
    verify: (_) => expect(repository.logoutCalls, 1),
  );

  blocTest<LogoutViewModel, LogoutState>(
    'com falha emite failure',
    build: () => LogoutViewModel(
      repository = FakeAuthRepository(
        logoutFailure: const AuthFailure(AuthFailureType.storage),
      ),
    ),
    act: (viewModel) => viewModel.logout(),
    expect: () => const [
      LogoutState(status: LogoutStatus.running),
      LogoutState(status: LogoutStatus.failure),
    ],
  );

  blocTest<LogoutViewModel, LogoutState>(
    'ignora um novo logout enquanto o anterior está em andamento',
    build: () => LogoutViewModel(repository = FakeAuthRepository()),
    seed: () => const LogoutState(status: LogoutStatus.running),
    act: (viewModel) => viewModel.logout(),
    expect: () => const <LogoutState>[],
    verify: (_) => expect(repository.logoutCalls, 0),
  );

  blocTest<LogoutViewModel, LogoutState>(
    'depois de uma falha, um novo logout é enviado',
    build: () => LogoutViewModel(repository = FakeAuthRepository()),
    seed: () => const LogoutState(status: LogoutStatus.failure),
    act: (viewModel) => viewModel.logout(),
    expect: () => const [
      LogoutState(status: LogoutStatus.running),
      LogoutState(),
    ],
  );

  test('duas chamadas seguidas fazem um logout só', () async {
    final completer = Completer<void>();
    repository = FakeAuthRepository(logoutCompleter: completer);
    final viewModel = LogoutViewModel(repository);

    final first = viewModel.logout();
    final second = viewModel.logout();
    completer.complete();
    await Future.wait([first, second]);

    expect(repository.logoutCalls, 1);
    await viewModel.close();
  });

  test('fechar o ViewModel durante o logout não gera erro', () async {
    final completer = Completer<void>();
    repository = FakeAuthRepository(logoutCompleter: completer);
    final viewModel = LogoutViewModel(repository);

    final logout = viewModel.logout();
    await viewModel.close();
    completer.complete();

    await expectLater(logout, completes);
  });

  test('logout com o ViewModel já fechado não faz nada', () async {
    repository = FakeAuthRepository();
    final viewModel = LogoutViewModel(repository);
    await viewModel.close();

    await expectLater(viewModel.logout(), completes);
    expect(repository.logoutCalls, 0);
  });
}
