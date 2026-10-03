import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
import 'package:matrix_messenger/features/auth/ui/login/view_models/login_state.dart';
import 'package:matrix_messenger/features/auth/ui/login/view_models/login_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_auth_repository.dart';

void main() {
  late FakeAuthRepository repository;

  tearDown(() => repository.dispose());

  Future<void> submit(LoginViewModel viewModel) => viewModel.login(
    homeserver: 'matrix.org',
    username: 'alice',
    password: 'secret',
  );

  test('estado inicial é idle', () {
    repository = FakeAuthRepository();
    expect(LoginViewModel(repository).state, const LoginState());
  });

  blocTest<LoginViewModel, LoginState>(
    'com sucesso emite running e volta para idle',
    build: () => LoginViewModel(repository = FakeAuthRepository()),
    act: submit,
    expect: () => const [LoginState(status: LoginStatus.running), LoginState()],
  );

  blocTest<LoginViewModel, LoginState>(
    'credenciais inválidas emitem failure com o tipo da falha',
    build: () => LoginViewModel(
      repository = FakeAuthRepository(
        loginFailure: const AuthFailure(AuthFailureType.invalidCredentials),
      ),
    ),
    act: submit,
    expect: () => const [
      LoginState(status: LoginStatus.running),
      LoginState(
        status: LoginStatus.failure,
        failureType: AuthFailureType.invalidCredentials,
      ),
    ],
  );

  blocTest<LoginViewModel, LoginState>(
    'erro que não é AuthFailure vira falha desconhecida',
    build: () => LoginViewModel(
      repository = FakeAuthRepository(loginFailure: Exception('boom')),
    ),
    act: submit,
    expect: () => const [
      LoginState(status: LoginStatus.running),
      LoginState(
        status: LoginStatus.failure,
        failureType: AuthFailureType.unknown,
      ),
    ],
  );

  blocTest<LoginViewModel, LoginState>(
    'ignora um novo login enquanto o anterior está em andamento',
    build: () => LoginViewModel(repository = FakeAuthRepository()),
    seed: () => const LoginState(status: LoginStatus.running),
    act: submit,
    expect: () => const <LoginState>[],
    verify: (_) => expect(repository.loginCalls, isEmpty),
  );

  blocTest<LoginViewModel, LoginState>(
    'depois de uma falha, um novo login é enviado',
    build: () => LoginViewModel(repository = FakeAuthRepository()),
    seed: () => const LoginState(
      status: LoginStatus.failure,
      failureType: AuthFailureType.invalidCredentials,
    ),
    act: submit,
    expect: () => const [LoginState(status: LoginStatus.running), LoginState()],
  );

  test('duas chamadas seguidas fazem um login só', () async {
    final completer = Completer<void>();
    repository = FakeAuthRepository(loginCompleter: completer);
    final viewModel = LoginViewModel(repository);

    final first = submit(viewModel);
    final second = submit(viewModel);
    completer.complete();
    await Future.wait([first, second]);

    expect(repository.loginCalls, hasLength(1));
    await viewModel.close();
  });

  test('repassa os dados do formulário ao repository', () async {
    repository = FakeAuthRepository();
    final viewModel = LoginViewModel(repository);

    await viewModel.login(
      homeserver: 'example.org',
      username: 'bob',
      password: 'pw',
    );

    expect(repository.loginCalls.single, (
      homeserver: 'example.org',
      username: 'bob',
      password: 'pw',
    ));
    await viewModel.close();
  });

  test('fechar o ViewModel durante o login não gera erro', () async {
    final completer = Completer<void>();
    repository = FakeAuthRepository(loginCompleter: completer);
    final viewModel = LoginViewModel(repository);

    final login = submit(viewModel);
    await viewModel.close();
    completer.complete();

    await expectLater(login, completes);
  });
}
