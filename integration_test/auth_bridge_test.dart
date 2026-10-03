import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix_messenger/app/app.dart';
import 'package:matrix_messenger/config/dependencies.dart';
import 'package:matrix_messenger/src/rust/api/auth.dart';
import 'package:matrix_messenger/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dataDir;

  setUpAll(() async => RustLib.init());

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('matrix_messenger_it_');
  });

  tearDown(() async => dataDir.delete(recursive: true));

  test('sem sessão salva, restoreSession devolve null', () async {
    expect(await MatrixClient.restoreSession(dataDir: dataDir.path), isNull);
  });

  test('erro do Rust chega ao Dart como AuthError tipado', () async {
    await expectLater(
      MatrixClient.login(
        homeserver: 'isto não é um servidor',
        username: 'alice',
        password: 'senha',
        dataDir: dataDir.path,
      ),
      throwsA(
        isA<AuthError>().having(
          (e) => e.kind,
          'kind',
          AuthErrorKind.invalidHomeserver,
        ),
      ),
    );
  });

  testWidgets('app abre no login e mostra o erro vindo do Rust', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: providers(dataDir: () async => dataDir.path),
        child: const MessengerApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login_homeserver')),
      'isto não é um servidor',
    );
    await tester.enterText(find.byKey(const Key('login_username')), 'alice');
    await tester.enterText(find.byKey(const Key('login_password')), 'senha');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Endereço de servidor inválido'),
      findsOneWidget,
    );
  });
}
