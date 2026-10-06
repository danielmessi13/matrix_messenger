import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/message_tile.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/models/message.dart';

void main() {
  Future<({List<String> retried, List<String> cancelled})> pump(
    WidgetTester tester,
    MessageItem message, {
    bool succeeds = true,
    bool compact = false,
  }) async {
    useDesktopSize(tester);
    final retried = <String>[];
    final cancelled = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: MessageTile(
            message: message,
            compact: compact,
            onRetry: () async {
              retried.add(message.id);
              return succeeds;
            },
            onCancel: () async {
              cancelled.add(message.id);
              return succeeds;
            },
          ),
        ),
      ),
    );
    return (retried: retried, cancelled: cancelled);
  }

  MessageItem own(SendState state, {List<String> readBy = const []}) =>
      MessageItem(
        id: 'txn',
        senderId: '@alice:matrix.org',
        senderName: 'Alice',
        isOwn: true,
        timestamp: DateTime(2026, 10, 4, 10, 21),
        kind: MessageKind.text,
        body: 'oi',
        sendState: state,
        readBy: readBy,
      );

  testWidgets('mensagem de outra pessoa: nome, horário e texto', (
    tester,
  ) async {
    await pump(tester, kOtherMessage);

    expect(find.text('Diego Alves'), findsOneWidget);
    expect(find.text('10:05'), findsOneWidget);
    expect(find.textContaining('A integração com o gateway'), findsOneWidget);
    expect(find.byTooltip('Em breve'), findsOneWidget);
    expect(find.text('VOCÊ'), findsNothing);
  });

  testWidgets('mensagem própria: etiqueta e "Lida por"', (tester) async {
    await pump(tester, kOwnMessage);

    expect(find.text('VOCÊ'), findsOneWidget);
    expect(find.text('✓✓ Lida por Carla e Diego'), findsOneWidget);
  });

  testWidgets('estados de envio', (tester) async {
    await pump(tester, own(SendState.sending));
    expect(find.text('Enviando…'), findsOneWidget);

    await pump(tester, own(SendState.sent));
    expect(find.text('Enviada'), findsOneWidget);
  });

  testWidgets('falha reenviável: tentar de novo e cancelar', (tester) async {
    final calls = await pump(tester, own(SendState.failed));

    expect(find.text('Não enviada'), findsOneWidget);
    await tester.tap(find.byKey(const Key('message_retry')));
    await tester.tap(find.byKey(const Key('message_cancel')));

    expect(calls.retried, ['txn']);
    expect(calls.cancelled, ['txn']);
  });

  testWidgets('falha ao reenviar avisa', (tester) async {
    await pump(tester, own(SendState.failed), succeeds: false);

    await tester.tap(find.byKey(const Key('message_retry')));
    await tester.pump();

    expect(find.text('Não foi possível reenviar.'), findsOneWidget);
  });

  testWidgets('falha ao cancelar avisa', (tester) async {
    await pump(tester, own(SendState.failed), succeeds: false);

    await tester.tap(find.byKey(const Key('message_cancel')));
    await tester.pump();

    expect(find.text('Não foi possível cancelar o envio.'), findsOneWidget);
  });

  testWidgets('compacta não mostra "Responder em thread"', (tester) async {
    await pump(tester, kOtherMessage, compact: true);

    expect(find.text('Diego Alves'), findsOneWidget);
    expect(find.byTooltip('Em breve'), findsNothing);
  });

  testWidgets('rejeitada: só cancelar', (tester) async {
    await pump(tester, own(SendState.rejected));

    expect(find.byKey(const Key('message_retry')), findsNothing);
    expect(find.byKey(const Key('message_cancel')), findsOneWidget);
  });

  testWidgets('tipo sem texto mostra a descrição', (tester) async {
    await pump(
      tester,
      MessageItem(
        id: '\$x',
        senderId: '@bob:b.c',
        senderName: 'Bob',
        isOwn: false,
        timestamp: DateTime(2026, 10, 4, 9),
        kind: MessageKind.redacted,
      ),
    );

    expect(find.text('Mensagem apagada'), findsOneWidget);
  });

  testWidgets('editada mostra a marca', (tester) async {
    await pump(
      tester,
      MessageItem(
        id: '\$e',
        senderId: '@bob:b.c',
        senderName: 'Bob',
        isOwn: false,
        timestamp: DateTime(2026, 10, 4, 9),
        kind: MessageKind.text,
        body: 'corrigido',
        edited: true,
      ),
    );

    expect(find.textContaining('(editada)'), findsOneWidget);
  });

  testWidgets('resposta mostra a citação acima do texto', (tester) async {
    await pump(
      tester,
      MessageItem(
        id: '\$2',
        senderId: '@bob:b.c',
        senderName: 'Bob',
        isOwn: false,
        timestamp: DateTime(2026, 10, 4, 10, 21),
        kind: MessageKind.text,
        body: 'concordo',
        replyTo: const ReplyPreview(
          state: ReplyState.ready,
          senderName: 'Diego Alves',
          kind: MessageKind.text,
          body: 'vamos subir hoje?',
        ),
      ),
    );

    final quote = find.byKey(const Key('message_reply_quote'));
    expect(
      find.descendant(of: quote, matching: find.text('Diego Alves')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quote, matching: find.text('vamos subir hoje?')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(quote).dy,
      lessThan(tester.getTopLeft(find.textContaining('concordo')).dy),
    );
  });

  testWidgets('mensagem sem resposta não mostra citação', (tester) async {
    await pump(tester, kOtherMessage);

    expect(find.byKey(const Key('message_reply_quote')), findsNothing);
  });
}
