import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
import 'package:matrix_messenger/features/auth/ui/login/view_models/login_state.dart';
import 'package:matrix_messenger/features/auth/ui/login/view_models/login_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../../../../testing/fakes/services/fake_browser_launcher.dart';

void main() {
  late FakeAuthRepository repository;
  late FakeBrowserLauncher launcher;

  setUp(() => launcher = FakeBrowserLauncher());

  tearDown(() => repository.dispose());

  Future<void> submit(LoginViewModel viewModel) => viewModel.login(
    homeserver: 'matrix.org',
    username: 'alice',
    password: 'secret',
  );

  test('estado inicial é idle', () {
    repository = FakeAuthRepository();
    expect(LoginViewModel(repository, launcher).state, const LoginState());
  });

  blocTest<LoginViewModel, LoginState>(
    'com sucesso emite running e volta para idle',
    build: () => LoginViewModel(repository = FakeAuthRepository(), launcher),
    act: submit,
    expect: () => const [LoginState(status: LoginStatus.running), LoginState()],
  );

  blocTest<LoginViewModel, LoginState>(
    'credenciais inválidas emitem failure com o tipo da falha',
    build: () => LoginViewModel(
      repository = FakeAuthRepository(
        loginFailure: const AuthFailure(AuthFailureType.invalidCredentials),
      ),
      launcher,
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
      launcher,
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
    build: () => LoginViewModel(repository = FakeAuthRepository(), launcher),
    seed: () => const LoginState(status: LoginStatus.running),
    act: submit,
    expect: () => const <LoginState>[],
    verify: (_) => expect(repository.loginCalls, isEmpty),
  );

  blocTest<LoginViewModel, LoginState>(
    'depois de uma falha, um novo login é enviado',
    build: () => LoginViewModel(repository = FakeAuthRepository(), launcher),
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
    final viewModel = LoginViewModel(repository, launcher);

    final first = submit(viewModel);
    final second = submit(viewModel);
    completer.complete();
    await Future.wait([first, second]);

    expect(repository.loginCalls, hasLength(1));
    await viewModel.close();
  });

  test('repassa os dados do formulário ao repository', () async {
    repository = FakeAuthRepository();
    final viewModel = LoginViewModel(repository, launcher);

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
    final viewModel = LoginViewModel(repository, launcher);

    final login = submit(viewModel);
    await viewModel.close();
    completer.complete();

    await expectLater(login, completes);
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  final authorizationUrl = Uri.parse(
    'https://account.matrix.org/authorize?state=abc',
  );

  LoginState awaiting() => LoginState(
    status: LoginStatus.awaitingBrowser,
    authorizationUrl: authorizationUrl,
  );

  test('depois de uma sessão revogada começa mostrando o motivo', () {
    repository = FakeAuthRepository(
      lastSignOutReason: AuthFailureType.sessionRevoked,
    );
    expect(
      LoginViewModel(repository, launcher).state,
      const LoginState(
        status: LoginStatus.failure,
        failureType: AuthFailureType.sessionRevoked,
      ),
    );
  });

  group('loginWithBrowser', () {
    blocTest<LoginViewModel, LoginState>(
      'abre o navegador, espera e volta para idle no sucesso',
      build: () => LoginViewModel(repository = FakeAuthRepository(), launcher),
      act: (viewModel) => viewModel.loginWithBrowser(homeserver: 'matrix.org'),
      expect: () => [
        const LoginState(status: LoginStatus.running),
        awaiting(),
        const LoginState(),
      ],
      verify: (_) {
        expect(repository.browserLoginCalls, ['matrix.org']);
        expect(launcher.opened, [authorizationUrl]);
      },
    );

    blocTest<LoginViewModel, LoginState>(
      'acesso negado no navegador emite failure',
      build: () => LoginViewModel(
        repository = FakeAuthRepository(
          browserLoginFailure: const AuthFailure(
            AuthFailureType.authorizationDenied,
          ),
        ),
        launcher,
      ),
      act: (viewModel) => viewModel.loginWithBrowser(homeserver: 'matrix.org'),
      expect: () => [
        const LoginState(status: LoginStatus.running),
        awaiting(),
        const LoginState(
          status: LoginStatus.failure,
          failureType: AuthFailureType.authorizationDenied,
        ),
      ],
    );

    blocTest<LoginViewModel, LoginState>(
      'tempo esgotado emite failure',
      build: () => LoginViewModel(
        repository = FakeAuthRepository(
          browserLoginFailure: const AuthFailure(AuthFailureType.timedOut),
        ),
        launcher,
      ),
      act: (viewModel) => viewModel.loginWithBrowser(homeserver: 'matrix.org'),
      expect: () => [
        const LoginState(status: LoginStatus.running),
        awaiting(),
        const LoginState(
          status: LoginStatus.failure,
          failureType: AuthFailureType.timedOut,
        ),
      ],
    );

    blocTest<LoginViewModel, LoginState>(
      'cancelar volta para idle sem mensagem',
      build: () => LoginViewModel(
        repository = FakeAuthRepository(browserLoginCompleter: Completer()),
        launcher,
      ),
      act: (viewModel) async {
        unawaited(viewModel.loginWithBrowser(homeserver: 'matrix.org'));
        await flush();
        await viewModel.cancelBrowserLogin();
        await flush();
      },
      expect: () => [
        const LoginState(status: LoginStatus.running),
        awaiting(),
        const LoginState(),
      ],
      verify: (_) => expect(repository.cancelBrowserLoginCalls, 1),
    );

    blocTest<LoginViewModel, LoginState>(
      'navegador que não abre cancela o login e mostra o erro',
      build: () => LoginViewModel(
        repository = FakeAuthRepository(browserLoginCompleter: Completer()),
        launcher..result = false,
      ),
      act: (viewModel) async {
        unawaited(viewModel.loginWithBrowser(homeserver: 'matrix.org'));
        await flush();
        await flush();
      },
      expect: () => [
        const LoginState(status: LoginStatus.running),
        awaiting(),
        const LoginState(
          status: LoginStatus.failure,
          failureType: AuthFailureType.browserUnavailable,
        ),
      ],
      verify: (_) => expect(repository.cancelBrowserLoginCalls, 1),
    );

    blocTest<LoginViewModel, LoginState>(
      'launcher que lança exceção é tratado como navegador que não abre',
      build: () => LoginViewModel(
        repository = FakeAuthRepository(browserLoginCompleter: Completer()),
        launcher..error = ArgumentError('URL inesperada'),
      ),
      act: (viewModel) async {
        unawaited(viewModel.loginWithBrowser(homeserver: 'matrix.org'));
        await flush();
        await flush();
      },
      expect: () => [
        const LoginState(status: LoginStatus.running),
        awaiting(),
        const LoginState(
          status: LoginStatus.failure,
          failureType: AuthFailureType.browserUnavailable,
        ),
      ],
      verify: (_) => expect(repository.cancelBrowserLoginCalls, 1),
    );

    blocTest<LoginViewModel, LoginState>(
      'durante a espera ignora novos logins, pelo navegador ou por senha',
      build: () => LoginViewModel(repository = FakeAuthRepository(), launcher),
      seed: awaiting,
      act: (viewModel) async {
        await viewModel.loginWithBrowser(homeserver: 'matrix.org');
        await submit(viewModel);
      },
      expect: () => const <LoginState>[],
      verify: (_) {
        expect(repository.browserLoginCalls, isEmpty);
        expect(repository.loginCalls, isEmpty);
      },
    );

    blocTest<LoginViewModel, LoginState>(
      'abrir novamente usa a mesma URL',
      build: () => LoginViewModel(repository = FakeAuthRepository(), launcher),
      seed: awaiting,
      act: (viewModel) => viewModel.reopenBrowser(),
      expect: () => const <LoginState>[],
      verify: (_) => expect(launcher.opened, [authorizationUrl]),
    );

    blocTest<LoginViewModel, LoginState>(
      'cancelar fora da espera não chama o repository',
      build: () => LoginViewModel(repository = FakeAuthRepository(), launcher),
      act: (viewModel) => viewModel.cancelBrowserLogin(),
      expect: () => const <LoginState>[],
      verify: (_) => expect(repository.cancelBrowserLoginCalls, 0),
    );
  });

  blocTest<LoginViewModel, LoginState>(
    'repassa keepSignedIn ao repository',
    build: () => LoginViewModel(repository = FakeAuthRepository(), launcher),
    act: (viewModel) async {
      await viewModel.login(
        homeserver: 'matrix.org',
        username: 'alice',
        password: 'secret',
        keepSignedIn: false,
      );
      await viewModel.loginWithBrowser(
        homeserver: 'matrix.org',
        keepSignedIn: false,
      );
    },
    verify: (_) => expect(repository.keepSignedInCalls, [false, false]),
  );
}
