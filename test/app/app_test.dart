import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/app.dart';
import 'package:matrix_messenger/features/auth/data/repositories/auth_repository.dart';

import '../../testing/fakes/repositories/fake_auth_repository.dart';
import '../../testing/models/user_session.dart';

void main() {
  Future<void> pumpApp(
    WidgetTester tester,
    FakeAuthRepository repository,
  ) async {
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      RepositoryProvider<AuthRepository>.value(
        value: repository,
        child: const MessengerApp(),
      ),
    );
    await tester.pump();
  }

  testWidgets('sem sessão salva abre no login', (tester) async {
    await pumpApp(tester, FakeAuthRepository());

    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('com sessão salva abre na tela do usuário logado', (
    tester,
  ) async {
    await pumpApp(tester, FakeAuthRepository(savedSession: kUserSession));

    expect(find.text('@alice:matrix.org'), findsOneWidget);
  });
}
