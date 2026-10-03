import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
import 'package:matrix_messenger/features/auth/ui/logout/view_models/logout_view_model.dart';
import 'package:matrix_messenger/features/auth/ui/logout/widgets/logout_button.dart';

import '../../../../../../testing/fakes/repositories/fake_auth_repository.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester,
    FakeAuthRepository repository,
  ) async {
    final viewModel = LogoutViewModel(repository);
    addTearDown(viewModel.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [LogoutButton(viewModel: viewModel)]),
        ),
      ),
    );
  }

  IconButton findButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.byKey(const Key('logout')));

  testWidgets('tocar no botão chama o logout do repository', (tester) async {
    final repository = FakeAuthRepository();
    await pumpButton(tester, repository);

    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('clique duplo faz um logout só', (tester) async {
    final completer = Completer<void>();
    final repository = FakeAuthRepository(logoutCompleter: completer);
    await pumpButton(tester, repository);

    // Os dois toques acontecem no mesmo frame, antes de o botão ser desabilitado.
    await tester.tap(find.byKey(const Key('logout')));
    await tester.tap(find.byKey(const Key('logout')));
    completer.complete();
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
  });

  testWidgets('fica desabilitado enquanto o logout está em andamento', (
    tester,
  ) async {
    final completer = Completer<void>();
    await pumpButton(tester, FakeAuthRepository(logoutCompleter: completer));

    await tester.tap(find.byKey(const Key('logout')));
    await tester.pump();
    expect(findButton(tester).onPressed, isNull);

    completer.complete();
    await tester.pumpAndSettle();
    expect(findButton(tester).onPressed, isNotNull);
  });

  testWidgets('falha mostra aviso e permite tentar de novo', (tester) async {
    final repository = FakeAuthRepository(
      logoutFailure: const AuthFailure(AuthFailureType.storage),
    );
    await pumpButton(tester, repository);

    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível sair.'), findsOneWidget);
    expect(findButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 2);
  });
}
