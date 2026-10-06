import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/recovery/domain/models/recovery_failure.dart';
import 'package:matrix_messenger/features/recovery/ui/view_models/recovery_state.dart';
import 'package:matrix_messenger/features/recovery/ui/view_models/recovery_view_model.dart';
import 'package:matrix_messenger/features/recovery/ui/widgets/recovery_dialog.dart';

import '../../../../../testing/fakes/repositories/fake_recovery_repository.dart';

void main() {
  late FakeRecoveryRepository repository;
  late RecoveryViewModel viewModel;

  const keyField = Key('recovery_key');
  const invalidKeyText =
      'Essa chave não confere. Confira se copiou todos os grupos.';

  setUp(() => repository = FakeRecoveryRepository());

  tearDown(() => repository.dispose());

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpHost(WidgetTester tester) async {
    viewModel = RecoveryViewModel(repository);
    addTearDown(viewModel.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showRecoveryDialog(context, viewModel),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await openDialog(tester);
  }

  FilledButton submitButton(WidgetTester tester) => tester.widget(
    find.descendant(
      of: find.byKey(const Key('recovery_submit')),
      matching: find.byType(FilledButton),
    ),
  );

  Future<void> submit(WidgetTester tester, String key) async {
    await tester.enterText(find.byKey(keyField), key);
    await tester.pump();
    await tester.tap(find.byKey(const Key('recovery_submit')));
  }

  testWidgets('Desbloquear fica inativo com o campo vazio ou só espaços', (
    tester,
  ) async {
    await pumpHost(tester);
    expect(submitButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(keyField), '   \n ');
    await tester.pump();
    expect(submitButton(tester).onPressed, isNull);

    await tester.enterText(find.byKey(keyField), 'EsTR');
    await tester.pump();
    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('Enter envia uma vez e chega ao sucesso', (tester) async {
    await pumpHost(tester);
    await tester.enterText(find.byKey(keyField), 'EsTR mwqJ');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(repository.recoveredWith, ['EsTR mwqJ']);
    expect(find.text('Mensagens desbloqueadas'), findsOneWidget);
  });

  testWidgets('Shift+Enter também envia', (tester) async {
    await pumpHost(tester);
    await tester.enterText(find.byKey(keyField), 'EsTR mwqJ');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(repository.recoveredWith, ['EsTR mwqJ']);
    expect(find.text('Mensagens desbloqueadas'), findsOneWidget);
  });

  testWidgets('chave começa oculta e o olho alterna sem mexer no texto', (
    tester,
  ) async {
    await pumpHost(tester);
    bool obscured() =>
        tester.widget<TextField>(find.byKey(keyField)).obscureText;
    String text() =>
        tester.widget<TextField>(find.byKey(keyField)).controller!.text;
    expect(obscured(), isTrue);

    await tester.enterText(find.byKey(keyField), 'EsTR mwqJ');
    await tester.tap(find.byKey(const Key('recovery_toggle_visibility')));
    await tester.pump();
    await tester.pump();
    expect(obscured(), isFalse);
    expect(text(), 'EsTR mwqJ');

    await tester.tap(find.byKey(const Key('recovery_toggle_visibility')));
    await tester.pump();
    await tester.pump();
    expect(obscured(), isTrue);
    expect(text(), 'EsTR mwqJ');
  });

  testWidgets('reabrir o diálogo volta a ocultar a chave', (tester) async {
    await pumpHost(tester);
    await tester.tap(find.byKey(const Key('recovery_toggle_visibility')));
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(keyField)).obscureText, isFalse);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await openDialog(tester);

    expect(tester.widget<TextField>(find.byKey(keyField)).obscureText, isTrue);
  });

  testWidgets('chave inválida mostra o erro e mantém o texto', (tester) async {
    repository.recoverResult = const Result.error(
      RecoveryFailure(RecoveryFailureType.invalidKey),
    );
    await pumpHost(tester);

    await submit(tester, 'errada');
    await tester.pumpAndSettle();

    expect(find.text(invalidKeyText), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(keyField)).controller!.text,
      'errada',
    );
  });

  testWidgets('falha de rede tem mensagem própria', (tester) async {
    repository.recoverResult = const Result.error(
      RecoveryFailure(RecoveryFailureType.network),
    );
    await pumpHost(tester);

    await submit(tester, 'EsTR');
    await tester.pumpAndSettle();

    expect(
      find.text('Não foi possível falar com o servidor. Tente de novo.'),
      findsOneWidget,
    );
    expect(find.text(invalidKeyText), findsNothing);
  });

  testWidgets('editar depois do erro limpa a mensagem', (tester) async {
    repository.recoverResult = const Result.error(
      RecoveryFailure(RecoveryFailureType.invalidKey),
    );
    await pumpHost(tester);
    await submit(tester, 'errada');
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(keyField), 'errada2');
    await tester.pump();

    expect(find.text(invalidKeyText), findsNothing);
    expect(viewModel.state.submit, RecoverySubmit.idle);
  });

  testWidgets('Esc e Cancelar fecham sem liberar o cartão', (tester) async {
    await pumpHost(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery_dialog')), findsNothing);

    await openDialog(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recovery_dialog')), findsNothing);
    expect(viewModel.state.unlocked, isFalse);
  });

  testWidgets('reabrir não mostra o erro anterior', (tester) async {
    repository.recoverResult = const Result.error(
      RecoveryFailure(RecoveryFailureType.invalidKey),
    );
    await pumpHost(tester);
    await submit(tester, 'errada');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await openDialog(tester);

    expect(find.text(invalidKeyText), findsNothing);
  });

  testWidgets('descriptografando não tem botões nem fecha', (tester) async {
    repository.gate = Completer<void>();
    await pumpHost(tester);

    await submit(tester, 'EsTR');
    await tester.pump();

    expect(find.text('Desbloqueando mensagens'), findsOneWidget);
    expect(find.byKey(const Key('recovery_progress')), findsOneWidget);
    expect(find.text('Cancelar'), findsNothing);
    expect(find.byKey(const Key('recovery_submit')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.byKey(const Key('recovery_dialog')), findsOneWidget);

    repository.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Mensagens desbloqueadas'), findsOneWidget);
  });

  testWidgets('Voltar às conversas fecha e libera o cartão', (tester) async {
    await pumpHost(tester);
    await submit(tester, 'EsTR');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recovery_finish')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery_dialog')), findsNothing);
    expect(viewModel.state.unlocked, isTrue);
  });

  testWidgets('clique fora no sucesso também libera o cartão', (tester) async {
    await pumpHost(tester);
    await submit(tester, 'EsTR');
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery_dialog')), findsNothing);
    expect(viewModel.state.unlocked, isTrue);
  });

  testWidgets('Enter no sucesso volta às conversas', (tester) async {
    await pumpHost(tester);
    await submit(tester, 'EsTR');
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recovery_dialog')), findsNothing);
    expect(viewModel.state.unlocked, isTrue);
  });
}
