import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/recovery/data/repositories/recovery_repository.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_failure.dart';
import 'package:matrix_messenger/features/recovery/ui/widgets/setup_recovery_dialog.dart';

import '../../../../../testing/fakes/repositories/fake_recovery_repository.dart';

void main() {
  late FakeRecoveryRepository repository;

  const dialog = Key('setup_recovery_dialog');
  const create = Key('setup_recovery_create');
  const confirm = Key('setup_recovery_confirm');
  const finish = Key('setup_recovery_finish');

  setUp(() => repository = FakeRecoveryRepository());

  tearDown(() => repository.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      RepositoryProvider<RecoveryRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSetupRecoveryDialog(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> createKey(WidgetTester tester) async {
    await tester.tap(find.byKey(create));
    await tester.pumpAndSettle();
  }

  testWidgets('abre na explicação e Esc fecha', (tester) async {
    await open(tester);

    expect(find.text('Configurar recuperação'), findsOneWidget);
    expect(find.text('Gerar chave'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(dialog), findsNothing);
  });

  testWidgets('criando mostra a barra e não fecha com Esc', (tester) async {
    repository.setupGate = Completer<void>();
    await open(tester);

    await tester.tap(find.byKey(create));
    await tester.pump();

    expect(find.byKey(const Key('setup_recovery_progress')), findsOneWidget);
    expect(find.text('Criando o backup'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(dialog), findsOneWidget);

    repository.setupGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('toque duplo em Gerar chave chama uma vez', (tester) async {
    repository.setupGate = Completer<void>();
    await open(tester);

    await tester.tap(find.byKey(create));
    await tester.pump();
    // O botão já saiu da tela; um segundo create() viria de um toque antes do rebuild.
    expect(find.byKey(create), findsNothing);

    repository.setupGate!.complete();
    await tester.pumpAndSettle();

    expect(repository.setupCalls, 1);
  });

  testWidgets('mostra a chave e Concluir só com a caixa marcada', (
    tester,
  ) async {
    await open(tester);
    await createKey(tester);

    expect(find.text('Guarde sua chave de recuperação'), findsOneWidget);
    expect(find.text(kFakeRecoveryKey), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: find.byKey(finish),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(confirm));
    await tester.pump();
    await tester.tap(find.byKey(finish));
    await tester.pumpAndSettle();

    expect(find.byKey(dialog), findsNothing);
  });

  testWidgets('Esc não fecha a chave pronta sem confirmar', (tester) async {
    await open(tester);
    await createKey(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(dialog), findsOneWidget);

    await tester.tap(find.byKey(confirm));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(dialog), findsNothing);
  });

  testWidgets('Copiar grava a chave e mostra Copiada', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await open(tester);
    await createKey(tester);

    await tester.tap(find.byKey(const Key('setup_recovery_copy')));
    await tester.pump();

    expect(copied, [kFakeRecoveryKey]);
    expect(find.text('Copiada'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copiar'), findsOneWidget);
  });

  for (final (type, text, retry) in [
    (
      RecoveryFailureType.network,
      'Sem conexão com o servidor. Tente de novo.',
      true,
    ),
    (
      RecoveryFailureType.authRequired,
      'Seu servidor pediu a senha para ativar a verificação, e o app ainda '
          'não faz esse pedido.',
      false,
    ),
    (
      RecoveryFailureType.backupExists,
      'Esta conta já tem um backup criado por outro aplicativo. Configure a '
          'recuperação por ele.',
      false,
    ),
    (
      RecoveryFailureType.unknown,
      'Não foi possível configurar a recuperação.',
      true,
    ),
  ]) {
    testWidgets('erro $type', (tester) async {
      repository.setupResult = Result.error(RecoveryFailure(type));
      await open(tester);
      await createKey(tester);

      expect(find.text('Não deu certo'), findsOneWidget);
      expect(find.text(text), findsOneWidget);
      expect(
        find.byKey(const Key('setup_recovery_retry')),
        retry ? findsOneWidget : findsNothing,
      );
      expect(find.text('Fechar'), findsOneWidget);
    });
  }

  testWidgets('Tentar de novo chega à chave', (tester) async {
    repository.setupResult = const Result.error(
      RecoveryFailure(RecoveryFailureType.network),
    );
    await open(tester);
    await createKey(tester);

    repository.setupResult = const Result.ok(kFakeRecoveryKey);
    await tester.tap(find.byKey(const Key('setup_recovery_retry')));
    await tester.pumpAndSettle();

    expect(find.text(kFakeRecoveryKey), findsOneWidget);
    expect(repository.setupCalls, 2);
  });
}
