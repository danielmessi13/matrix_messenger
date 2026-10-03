import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
import 'package:matrix_messenger/features/auth/ui/auth_gate/view_models/auth_gate_state.dart';
import 'package:matrix_messenger/features/auth/ui/auth_gate/view_models/auth_gate_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../../../../testing/models/user_session.dart';

void main() {
  late FakeAuthRepository repository;

  tearDown(() => repository.dispose());

  test('estado inicial é a restauração da sessão', () {
    repository = FakeAuthRepository();
    expect(AuthGateViewModel(repository).state, const AuthGateRestoring());
  });

  blocTest<AuthGateViewModel, AuthGateState>(
    'com sessão salva emite authenticated',
    build: () => AuthGateViewModel(
      repository = FakeAuthRepository(savedSession: kUserSession),
    ),
    act: (viewModel) => viewModel.init(),
    expect: () => const [AuthGateAuthenticated(kUserSession)],
  );

  blocTest<AuthGateViewModel, AuthGateState>(
    'sem sessão salva emite unauthenticated',
    build: () => AuthGateViewModel(repository = FakeAuthRepository()),
    act: (viewModel) => viewModel.init(),
    expect: () => const [AuthGateUnauthenticated()],
  );

  blocTest<AuthGateViewModel, AuthGateState>(
    'falha na restauração leva ao login',
    build: () => AuthGateViewModel(
      repository = FakeAuthRepository(
        restoreFailure: const AuthFailure(AuthFailureType.storage),
      ),
    ),
    act: (viewModel) => viewModel.init(),
    expect: () => const [AuthGateUnauthenticated()],
  );

  blocTest<AuthGateViewModel, AuthGateState>(
    'login feito no repository leva à home',
    build: () => AuthGateViewModel(repository = FakeAuthRepository()),
    act: (viewModel) async {
      await viewModel.init();
      await repository.login(
        homeserver: 'matrix.org',
        username: 'alice',
        password: 'secret',
      );
    },
    expect: () => const [
      AuthGateUnauthenticated(),
      AuthGateAuthenticated(kUserSession),
    ],
  );

  blocTest<AuthGateViewModel, AuthGateState>(
    'logout feito no repository volta ao login',
    build: () => AuthGateViewModel(
      repository = FakeAuthRepository(savedSession: kUserSession),
    ),
    act: (viewModel) async {
      await viewModel.init();
      await repository.logout();
    },
    expect: () => const [
      AuthGateAuthenticated(kUserSession),
      AuthGateUnauthenticated(),
    ],
  );

  test('fechar durante a restauração não gera erro nem emite', () async {
    final completer = Completer<void>();
    repository = FakeAuthRepository(
      savedSession: kUserSession,
      restoreCompleter: completer,
    );
    final viewModel = AuthGateViewModel(repository);
    final states = <AuthGateState>[];
    viewModel.stream.listen(states.add);

    final init = viewModel.init();
    await viewModel.close();
    completer.complete();

    await expectLater(init, completes);
    expect(states, isEmpty);
  });

  test('fechar para de escutar a sessão do repository', () async {
    repository = FakeAuthRepository();
    final viewModel = AuthGateViewModel(repository);
    await viewModel.init();

    await viewModel.close();

    expect(repository.hasSessionListeners, isFalse);
    await expectLater(
      repository.login(
        homeserver: 'matrix.org',
        username: 'alice',
        password: 'secret',
      ),
      completes,
    );
  });
}
