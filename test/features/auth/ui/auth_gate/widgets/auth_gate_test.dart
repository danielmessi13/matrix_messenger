import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';
import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/features/auth/ui/auth_gate/view_models/auth_gate_view_model.dart';
import 'package:matrix_messenger/features/auth/ui/auth_gate/widgets/auth_gate.dart';

import '../../../../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../../../../testing/models/user_session.dart';

void main() {
  Future<void> pumpGate(
    WidgetTester tester,
    FakeAuthRepository repository,
  ) async {
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      RepositoryProvider<AuthRepository>.value(
        value: repository,
        child: MaterialApp(
          home: BlocProvider(
            create: (context) =>
                AuthGateViewModel(context.read<AuthRepository>())..init(),
            child: Builder(
              builder: (context) =>
                  AuthGate(viewModel: context.read<AuthGateViewModel>()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('sem sessão salva mostra o formulário de login', (tester) async {
    await pumpGate(tester, FakeAuthRepository());

    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('com sessão salva abre direto na tela do usuário logado', (
    tester,
  ) async {
    await pumpGate(tester, FakeAuthRepository(savedSession: kUserSession));

    expect(find.text('@alice:matrix.org'), findsOneWidget);
    expect(find.byKey(const Key('login_submit')), findsNothing);
  });

  testWidgets('login com sucesso troca para a tela do usuário logado', (
    tester,
  ) async {
    await pumpGate(tester, FakeAuthRepository());

    await tester.enterText(find.byKey(const Key('login_username')), 'alice');
    await tester.enterText(find.byKey(const Key('login_password')), 'secret');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(find.text('@alice:matrix.org'), findsOneWidget);
  });

  testWidgets('sair volta para o formulário de login', (tester) async {
    final repository = FakeAuthRepository(savedSession: kUserSession);
    await pumpGate(tester, repository);

    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('sessão nova sem passar pelo login atualiza a tela do usuário', (
    tester,
  ) async {
    const otherSession = UserSession(
      userId: '@bob:matrix.org',
      deviceId: 'DEVICE456',
    );
    final repository = FakeAuthRepository(
      savedSession: kUserSession,
      loginSession: otherSession,
    );
    await pumpGate(tester, repository);

    // Ex.: um novo login após soft logout, que cria outro device sem passar pelo logout.
    await repository.login(
      homeserver: 'matrix.org',
      username: 'bob',
      password: 'secret',
    );
    await tester.pumpAndSettle();

    expect(find.text('@bob:matrix.org'), findsOneWidget);
    expect(find.text('@alice:matrix.org'), findsNothing);
  });
}
