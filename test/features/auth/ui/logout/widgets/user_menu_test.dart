import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/auth/domain/models/auth_failure.dart';
import 'package:matrix_messenger/features/auth/ui/logout/view_models/logout_view_model.dart';
import 'package:matrix_messenger/features/auth/ui/logout/widgets/user_menu.dart';

import '../../../../../../testing/fakes/repositories/fake_auth_repository.dart';

void main() {
  Future<void> pumpMenu(
    WidgetTester tester,
    FakeAuthRepository repository,
  ) async {
    final viewModel = LogoutViewModel(repository);
    addTearDown(viewModel.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: UserMenu(viewModel: viewModel, userId: '@alice:matrix.org'),
          ),
        ),
      ),
    );
  }

  Future<void> tapLogout(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('user_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout')));
  }

  testWidgets('mostra iniciais e nome; o menu mostra o Matrix ID', (
    tester,
  ) async {
    await pumpMenu(tester, FakeAuthRepository());

    expect(find.text('AL'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('@alice:matrix.org'), findsNothing);

    await tester.tap(find.byKey(const Key('user_menu')));
    await tester.pumpAndSettle();

    expect(find.text('@alice:matrix.org'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
  });

  testWidgets('gatilho sem tooltip e com hover arredondado', (tester) async {
    await pumpMenu(tester, FakeAuthRepository());

    expect(find.byTooltip('Show menu'), findsNothing);
    final ink = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('user_menu')),
        matching: find.byType(InkWell),
      ),
    );
    expect(ink.borderRadius, BorderRadius.circular(21));
  });

  testWidgets('"Sair" chama o logout do repository', (tester) async {
    final repository = FakeAuthRepository();
    await pumpMenu(tester, repository);

    await tapLogout(tester);
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('fica desabilitado enquanto o logout está em andamento', (
    tester,
  ) async {
    final completer = Completer<void>();
    await pumpMenu(tester, FakeAuthRepository(logoutCompleter: completer));

    await tapLogout(tester);
    await tester.pumpAndSettle();
    final menu = tester.widget<PopupMenuButton<void>>(
      find.byKey(const Key('user_menu')),
    );
    expect(menu.enabled, isFalse);

    completer.complete();
    await tester.pumpAndSettle();
    final reenabled = tester.widget<PopupMenuButton<void>>(
      find.byKey(const Key('user_menu')),
    );
    expect(reenabled.enabled, isTrue);
  });

  testWidgets('falha mostra aviso e permite tentar de novo', (tester) async {
    final repository = FakeAuthRepository(
      logoutFailure: const AuthFailure(AuthFailureType.storage),
    );
    await pumpMenu(tester, repository);

    await tapLogout(tester);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível sair.'), findsOneWidget);

    await tester.tap(find.text('Tentar de novo'));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 2);
  });

  testWidgets('um novo logout esconde o aviso da falha anterior', (
    tester,
  ) async {
    final repository = FakeAuthRepository(
      logoutFailure: const AuthFailure(AuthFailureType.storage),
    );
    await pumpMenu(tester, repository);

    await tapLogout(tester);
    await tester.pumpAndSettle();
    expect(find.text('Não foi possível sair.'), findsOneWidget);

    repository.logoutFailure = null;
    await tapLogout(tester);
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 2);
    expect(find.text('Não foi possível sair.'), findsNothing);
  });
}
