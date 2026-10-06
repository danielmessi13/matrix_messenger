import 'package:flutter/gestures.dart';
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
    VoidCallback? onReply,
    VoidCallback? onStartThread,
    ValueChanged<String>? onQuoteTap,
  }) async {
    useDesktopSize(tester);
    final retried = <String>[];
    final cancelled = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          // O menu do hover fica 20 px acima do balão; sem margem sairia da tela.
          body: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: MessageTile(
              message: message,
              compact: compact,
              onReply: onReply,
              onStartThread: onStartThread,
              onQuoteTap: onQuoteTap,
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
    expect(find.text('VOCÊ'), findsNothing);
  });

  Future<void> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
  }

  testWidgets('hover mostra Responder e Thread', (tester) async {
    var replies = 0;
    var threads = 0;
    await pump(
      tester,
      kOtherMessage,
      onReply: () => replies++,
      onStartThread: () => threads++,
    );
    expect(find.text('Responder'), findsNothing);

    await hover(tester, find.textContaining('A integração'));
    await tester.tap(find.byKey(const Key('message_reply_\$other')));
    await tester.tap(find.byKey(const Key('message_thread_\$other')));

    expect((replies, threads), (1, 1));
  });

  testWidgets('sem onStartThread o menu só tem Responder', (tester) async {
    await pump(tester, kOtherMessage, onReply: () {});

    await hover(tester, find.textContaining('A integração'));

    expect(find.text('Responder'), findsOneWidget);
    expect(find.text('Thread'), findsNothing);
  });

  testWidgets('mensagem que não pode ser respondida não tem menu', (
    tester,
  ) async {
    await pump(
      tester,
      own(SendState.sending),
      onReply: () {},
      onStartThread: () {},
    );

    await hover(tester, find.text('oi'));

    expect(find.text('Responder'), findsNothing);
  });

  testWidgets('cabeçalho da citação leva à original', (tester) async {
    final tapped = <String>[];
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
          eventId: '\$1',
          state: ReplyState.ready,
          isOwn: true,
          senderName: 'Alice',
          kind: MessageKind.text,
          body: 'vamos subir hoje?',
        ),
      ),
      onQuoteTap: tapped.add,
    );

    expect(find.text('respondeu a você'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reply_quote_header')));

    expect(tapped, ['\$1']);
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

  testWidgets('compacta mantém o menu de hover', (tester) async {
    var replies = 0;
    await pump(tester, kOtherMessage, compact: true, onReply: () => replies++);

    await hover(tester, find.textContaining('A integração'));
    await tester.tap(find.byKey(const Key('message_reply_\$other')));

    expect(replies, 1);
  });

  MessageItem quoted(String name, String body) => MessageItem(
    id: '\$q',
    senderId: '@bob:b.c',
    senderName: 'Bob',
    isOwn: false,
    timestamp: DateTime(2026, 10, 4, 10, 21),
    kind: MessageKind.text,
    body: body,
    replyTo: ReplyPreview(
      eventId: '\$1',
      state: ReplyState.ready,
      senderName: name,
      kind: MessageKind.text,
      body: 'ok',
    ),
  );

  testWidgets('cabeçalho da citação ocupa a largura do cartão', (tester) async {
    await pump(
      tester,
      quoted('Ana', 'um corpo bem mais largo que o cabeçalho da citação'),
    );

    final card = tester.getSize(find.byKey(const Key('message_reply_quote')));
    final header = tester.getSize(find.byKey(const Key('reply_quote_header')));

    expect(header.width, closeTo(card.width - 2, 2));
  });

  testWidgets('citação longa não alarga o cartão de uma resposta curta', (
    tester,
  ) async {
    await pump(
      tester,
      MessageItem(
        id: '\$q',
        senderId: '@bob:b.c',
        senderName: 'Bob',
        isOwn: false,
        timestamp: DateTime(2026, 10, 4, 10, 21),
        kind: MessageKind.text,
        body: 'ok',
        replyTo: ReplyPreview(
          eventId: '\$1',
          state: ReplyState.ready,
          senderName: 'Ana',
          kind: MessageKind.text,
          body: 'uma mensagem original bem comprida ' * 6,
        ),
      ),
    );

    final card = tester.getSize(find.byKey(const Key('message_reply_quote')));
    expect(card.width, lessThan(260));
  });

  testWidgets('menu fica junto do balão, não no canto da linha', (
    tester,
  ) async {
    await pump(
      tester,
      MessageItem(
        id: '\$curta',
        senderId: '@bob:b.c',
        senderName: 'Bob',
        isOwn: false,
        timestamp: DateTime(2026, 10, 4, 10, 21),
        kind: MessageKind.text,
        body: 'oi',
        canReply: true,
      ),
      onReply: () {},
    );

    await hover(tester, find.text('oi'));

    final time = tester.getRect(find.text('10:21'));
    final bar = tester.getRect(find.byKey(const Key('message_reply_\$curta')));
    // Canto superior direito, crescendo para a direita.
    expect(bar.left, greaterThan(time.right - 20));
    expect(bar.left - time.right, lessThan(20));
    expect(time.top - bar.bottom, lessThan(0));
    expect(find.byIcon(Icons.reply), findsOneWidget);
    expect(find.textContaining('↩'), findsNothing);
  });

  testWidgets(
    'menu de mensagem própria curta fica no canto superior esquerdo, dentro da tela',
    (
      tester,
    ) async {
      await pump(
        tester,
        MessageItem(
          id: '\$minha',
          senderId: '@alice:matrix.org',
          senderName: 'Alice',
          isOwn: true,
          timestamp: DateTime(2026, 10, 4, 10, 21),
          kind: MessageKind.text,
          body: 'vdd',
          canReply: true,
        ),
        onReply: () {},
        onStartThread: () {},
      );

      await hover(tester, find.text('vdd'));

      final time = tester.getRect(find.text('10:21'));
      final reply = tester.getRect(
        find.byKey(const Key('message_reply_\$minha')),
      );
      final thread = tester.getRect(
        find.byKey(const Key('message_thread_\$minha')),
      );
      final screen = tester.getRect(find.byType(Scaffold));
      expect(thread.right, lessThan(time.left + 20));
      expect(reply.left, greaterThan(screen.left));
      expect(thread.right, lessThanOrEqualTo(screen.right));
    },
  );

  testWidgets('botão do menu destaca o fundo e o texto no hover', (
    tester,
  ) async {
    await pump(tester, kOtherMessage, onReply: () {}, onStartThread: () {});
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.textContaining('A integração')));
    await tester.pump();

    final colors = tester.element(find.byType(Scaffold)).colors;
    final reply = find.byKey(const Key('message_reply_\$other'));
    final label = find.descendant(of: reply, matching: find.text('Responder'));
    final icon = find.descendant(of: reply, matching: find.byType(Icon));
    Color? background() => tester
        .widgetList<DecoratedBox>(
          find.descendant(of: reply, matching: find.byType(DecoratedBox)),
        )
        .map((box) => (box.decoration as BoxDecoration).color)
        .whereType<Color>()
        .firstOrNull;
    Color? labelColor() => tester.widget<Text>(label).style?.color;
    Color? iconColor() => tester.widget<Icon>(icon).color;

    expect(background(), isNull);
    expect(iconColor(), colors.textSecondary);

    await mouse.moveTo(tester.getCenter(reply));
    await tester.pumpAndSettle();
    expect(background(), colors.surfaceHigh);
    expect(labelColor(), colors.textPrimary);
    expect(iconColor(), colors.textPrimary);

    await mouse.moveTo(
      tester.getCenter(find.byKey(const Key('message_thread_\$other'))),
    );
    await tester.pumpAndSettle();
    expect(background(), isNull);
    expect(iconColor(), colors.textSecondary);
  });

  testWidgets('menu aparece no espaço vazio da linha, ao lado do balão', (
    tester,
  ) async {
    await pump(
      tester,
      MessageItem(
        id: '\$curta',
        senderId: '@bob:b.c',
        senderName: 'Bob',
        isOwn: false,
        timestamp: DateTime(2026, 10, 4, 10, 21),
        kind: MessageKind.text,
        body: 'oi',
        canReply: true,
      ),
      onReply: () {},
    );
    final row = tester.getRect(find.byKey(const Key('message_\$curta')));
    final bubble = tester.getRect(find.text('Bob'));
    final side = Offset(row.right - 20, bubble.center.dy);
    expect(side.dx - bubble.right, greaterThan(300));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(side);
    await tester.pump();
    expect(find.byKey(const Key('message_reply_\$curta')), findsOneWidget);

    await mouse.moveTo(Offset(row.right - 20, row.bottom + 100));
    await tester.pump();
    expect(find.byKey(const Key('message_reply_\$curta')), findsNothing);
  });

  testWidgets('passar do balão para o menu mantém o menu aberto', (
    tester,
  ) async {
    var replies = 0;
    await pump(tester, kOtherMessage, onReply: () => replies++);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.textContaining('A integração')));
    await tester.pump();

    final button = find.byKey(const Key('message_reply_\$other'));
    await mouse.moveTo(tester.getCenter(button));
    await tester.pump();
    expect(button, findsOneWidget);
    await mouse.down(tester.getCenter(button));
    await mouse.up();
    await tester.pump();

    expect(replies, 1);
  });

  testWidgets('nome longo no cabeçalho não estoura em largura estreita', (
    tester,
  ) async {
    useDesktopSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: MessageTile(
              message: quoted('N' * 120, 'oi'),
              onRetry: () async => true,
              onCancel: () async => true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
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
          eventId: '\$x',
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
      find.descendant(
        of: quote,
        matching: find.textContaining('vamos subir hoje?'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: quote, matching: find.textContaining('concordo')),
      findsOneWidget,
    );
  });

  testWidgets('mensagem sem resposta não mostra citação', (tester) async {
    await pump(tester, kOtherMessage);

    expect(find.byKey(const Key('message_reply_quote')), findsNothing);
  });
}
