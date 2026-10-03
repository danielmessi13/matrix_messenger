import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
import 'package:matrix_messenger/features/auth/ui/login/view_models/login_view_model.dart';
import 'package:matrix_messenger/features/auth/ui/login/widgets/login_screen.dart';

import '../../../../../../testing/fakes/repositories/fake_auth_repository.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    FakeAuthRepository repository,
  ) async {
    final viewModel = LoginViewModel(repository);
    addTearDown(viewModel.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(viewModel: viewModel)),
    );
  }

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    String password = 'secret',
  }) async {
    await tester.enterText(find.byKey(const Key('login_username')), 'alice');
    await tester.enterText(find.byKey(const Key('login_password')), password);
    await tester.tap(find.byKey(const Key('login_submit')));
  }

  testWidgets('valida campos obrigatórios sem chamar o repository', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    await pumpScreen(tester, repository);

    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pump();

    expect(find.text('Informe o usuário.'), findsOneWidget);
    expect(find.text('Informe a senha.'), findsOneWidget);
    expect(repository.loginCalls, isEmpty);
  });

  testWidgets('mostra carregamento enquanto o login está em andamento', (
    tester,
  ) async {
    final completer = Completer<void>();
    final repository = FakeAuthRepository(loginCompleter: completer);
    await pumpScreen(tester, repository);

    await fillAndSubmit(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(repository.loginCalls, hasLength(1));
  });

  testWidgets('clique duplo no botão e Enter na senha fazem um login só', (
    tester,
  ) async {
    final completer = Completer<void>();
    final repository = FakeAuthRepository(loginCompleter: completer);
    await pumpScreen(tester, repository);

    await fillAndSubmit(tester);
    // Segundo envio no mesmo frame, antes de o botão ser redesenhado como desabilitado.
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    completer.complete();
    await tester.pumpAndSettle();

    expect(repository.loginCalls, hasLength(1));
  });

  testWidgets('mostra mensagem amigável quando a senha está errada', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      FakeAuthRepository(
        loginFailure: const AuthFailure(AuthFailureType.invalidCredentials),
      ),
    );

    await fillAndSubmit(tester, password: 'errada');
    await tester.pumpAndSettle();

    expect(find.text('Usuário ou senha incorretos.'), findsOneWidget);
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });
}
