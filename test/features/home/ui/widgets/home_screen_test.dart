import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';
import 'package:matrix_messenger/features/auth/domain/models/user_session.dart';
import 'package:matrix_messenger/features/home/ui/view_models/home_view_model.dart';
import 'package:matrix_messenger/features/home/ui/widgets/home_screen.dart';

import '../../../../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../../../../testing/models/user_session.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    FakeAuthRepository repository, {
    UserSession session = kUserSession,
  }) async {
    final viewModel = HomeViewModel(session);
    addTearDown(viewModel.close);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      RepositoryProvider<AuthRepository>.value(
        value: repository,
        child: MaterialApp(home: HomeScreen(viewModel: viewModel)),
      ),
    );
  }

  testWidgets('mostra o usuário e o device conectados', (tester) async {
    await pumpScreen(tester, FakeAuthRepository());

    expect(find.text('@alice:matrix.org'), findsOneWidget);
    expect(find.text('Device DEVICE123'), findsOneWidget);
    expect(find.byKey(const Key('session_not_saved')), findsNothing);
  });

  testWidgets('avisa quando a sessão não pôde ser salva', (tester) async {
    await pumpScreen(
      tester,
      FakeAuthRepository(),
      session: const UserSession(
        userId: '@alice:matrix.org',
        deviceId: 'DEVICE123',
        sessionSaved: false,
      ),
    );

    expect(find.byKey(const Key('session_not_saved')), findsOneWidget);
  });

  testWidgets('o botão de sair usa o repository do app', (tester) async {
    final repository = FakeAuthRepository(savedSession: kUserSession);
    await pumpScreen(tester, repository);

    await tester.tap(find.byKey(const Key('logout')));
    await tester.pumpAndSettle();

    expect(repository.logoutCalls, 1);
  });
}
