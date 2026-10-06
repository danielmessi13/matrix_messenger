import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/message_input.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/models/message.dart';

void main() {
  Future<List<String>> pump(
    WidgetTester tester, {
    bool succeed = true,
    MessageItem? replyTo,
    VoidCallback? onCancelReply,
    bool compact = false,
  }) async {
    useDesktopSize(tester);
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MessageInput(
              placeholder: 'Escrever para #lançamento-q4…',
              replyTo: replyTo,
              onCancelReply: onCancelReply,
              compact: compact,
              onSend: (text) async {
                sent.add(text);
                return succeed;
              },
            ),
          ),
        ),
      ),
    );
    return sent;
  }

  TextField field(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('message_field')));

  testWidgets('placeholder com o nome da sala e enviar desabilitado vazio', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Escrever para #lançamento-q4…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('message_send')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Enter envia, limpa e mantém o foco', (tester) async {
    final sent = await pump(tester);

    await tester.enterText(find.byKey(const Key('message_field')), 'olá');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, ['olá']);
    expect(field(tester).controller!.text, isEmpty);
    expect(field(tester).focusNode!.hasFocus, isTrue);
  });

  // Em widget test o Enter não digita a quebra de linha; aqui só dá para provar que não envia.
  testWidgets('Shift+Enter não envia', (tester) async {
    final sent = await pump(tester);

    await tester.enterText(find.byKey(const Key('message_field')), 'linha 1');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sent, isEmpty);
    expect(field(tester).controller!.text, startsWith('linha 1'));
  });

  testWidgets('Enter com campo vazio ou só espaços não envia', (tester) async {
    final sent = await pump(tester);

    await tester.enterText(find.byKey(const Key('message_field')), '   ');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, isEmpty);
    expect(field(tester).controller!.text, '   ');
  });

  testWidgets('botões de formatação envolvem a seleção', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('message_field')), 'oi mundo');
    final controller = field(tester).controller!;

    controller.selection = const TextSelection(baseOffset: 3, extentOffset: 8);
    await tester.tap(find.byKey(const Key('format_bold')));
    expect(controller.text, 'oi **mundo**');

    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.tap(find.byKey(const Key('format_strike')));
    expect(controller.text, '~~~~oi **mundo**');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });

  testWidgets('lista insere "- " no início da linha', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('message_field')), 'itens\num');
    final controller = field(tester).controller!;
    controller.selection = const TextSelection.collapsed(offset: 8);

    await tester.tap(find.byKey(const Key('format_list')));

    expect(controller.text, 'itens\n- um');
  });

  testWidgets('falha ao enviar mostra aviso e mantém o texto', (tester) async {
    await pump(tester, succeed: false);

    await tester.enterText(find.byKey(const Key('message_field')), 'olá');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message_send')));
    await tester.pump();

    expect(find.text('Não foi possível enviar.'), findsOneWidget);
    expect(field(tester).controller!.text, 'olá');
  });

  testWidgets('desabilitado bloqueia campo, formatação e envio', (
    tester,
  ) async {
    useDesktopSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MessageInput(
            placeholder: 'Escrever para #lançamento-q4…',
            enabled: false,
            onSend: (_) async => true,
          ),
        ),
      ),
    );

    expect(field(tester).enabled, isFalse);
    for (final key in [
      'format_bold',
      'format_italic',
      'format_strike',
      'format_code',
      'format_list',
    ]) {
      final button = find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(IconButton),
      );
      expect(tester.widget<IconButton>(button).onPressed, isNull, reason: key);
    }
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('message_send')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('anexar envia imagem e mencionar fica para depois', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byTooltip('Enviar imagem'), findsOneWidget);
    expect(find.byTooltip('Em breve'), findsOneWidget);
  });

  Future<void> pumpWith(
    WidgetTester tester,
    Future<bool> Function(String) onSend, {
    double? width,
  }) async {
    useDesktopSize(tester);
    Widget input = MessageInput(
      placeholder: 'Escrever para #lançamento-q4…',
      onSend: onSend,
    );
    if (width != null) input = SizedBox(width: width, child: input);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(alignment: Alignment.bottomCenter, child: input),
        ),
      ),
    );
  }

  testWidgets(
    'envio pendente não reenvia e preserva o que foi digitado depois',
    (tester) async {
      final completer = Completer<bool>();
      final sent = <String>[];
      await pumpWith(tester, (text) {
        sent.add(text);
        return completer.future;
      });

      await tester.enterText(find.byKey(const Key('message_field')), 'olá');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(sent, ['olá']);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('message_send')))
            .onPressed,
        isNull,
      );

      await tester.enterText(
        find.byKey(const Key('message_field')),
        'olá mais',
      );
      completer.complete(true);
      await tester.pump();
      expect(field(tester).controller!.text, 'olá mais');

      await tester.enterText(find.byKey(const Key('message_field')), 'olá');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sent, ['olá', 'olá']);
    },
  );

  testWidgets('envio concluído limpa o campo se o texto não mudou', (
    tester,
  ) async {
    final completer = Completer<bool>();
    await pumpWith(tester, (_) => completer.future);

    await tester.enterText(find.byKey(const Key('message_field')), 'olá');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    completer.complete(true);
    await tester.pump();

    expect(field(tester).controller!.text, isEmpty);
  });

  testWidgets(
    'painel estreito mostra dica em linha própria e todos os botões',
    (tester) async {
      await pumpWith(tester, (_) async => true, width: 456);

      expect(tester.takeException(), isNull);
      expect(
        find.text('Enter envia · Shift + Enter nova linha'),
        findsOneWidget,
      );
      for (final key in [
        'format_bold',
        'format_italic',
        'format_strike',
        'format_code',
        'format_list',
        'attach_image',
        'message_send',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.byTooltip('Em breve'), findsOneWidget);
    },
  );

  testWidgets('Enter durante composição não envia', (tester) async {
    final sent = await pump(tester);
    await tester.enterText(find.byKey(const Key('message_field')), 'a');
    final controller = field(tester).controller!;
    controller.value = const TextEditingValue(
      text: 'a',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange(start: 0, end: 1),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, isEmpty);
  });

  testWidgets('Enter segurado não reenvia nem insere quebra', (tester) async {
    final sent = await pump(tester);
    await tester.enterText(find.byKey(const Key('message_field')), 'olá');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, ['olá']);
  });

  testWidgets('lista com cursor em 0 e texto iniciando em quebra', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('message_field')), '\nfoo');
    final controller = field(tester).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);

    await tester.tap(find.byKey(const Key('format_list')));

    expect(controller.text, '- \nfoo');
  });

  testWidgets('resposta mostra a barra e × cancela', (tester) async {
    var cancels = 0;
    await pump(tester, replyTo: kOtherMessage, onCancelReply: () => cancels++);

    expect(find.text('Respondendo a Diego Alves'), findsOneWidget);
    expect(find.textContaining('A integração com o gateway'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reply_cancel')));

    expect(cancels, 1);
  });

  testWidgets('começar uma resposta foca o campo', (tester) async {
    await pump(tester);
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      isNot('message_field'),
    );

    await pump(tester, replyTo: kOtherMessage);
    await tester.pump();

    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'message_field',
    );
  });

  testWidgets('compacto esconde formatação e dica', (tester) async {
    await pump(tester, compact: true);

    expect(find.byKey(const Key('format_bold')), findsNothing);
    expect(find.text('Enter envia · Shift + Enter nova linha'), findsNothing);
    expect(find.byKey(const Key('message_send')), findsOneWidget);
  });

  testWidgets('o + chama onAttachImage e espera enquanto anexa', (
    tester,
  ) async {
    useDesktopSize(tester);
    var attached = 0;
    Widget input({required bool attaching}) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MessageInput(
          placeholder: 'Escrever…',
          onSend: (_) async => true,
          onAttachImage: () => attached++,
          attaching: attaching,
        ),
      ),
    );
    IconButton plus() => tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const Key('attach_image')),
        matching: find.byType(IconButton),
      ),
    );

    await tester.pumpWidget(input(attaching: false));
    await tester.tap(find.byKey(const Key('attach_image')));
    expect(attached, 1);
    await tester.pumpWidget(input(attaching: true));

    expect(plus().onPressed, isNull);
  });
}
