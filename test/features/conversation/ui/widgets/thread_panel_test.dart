import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/thread/view_models/thread_view_model.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/thread_panel.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../testing/models/message.dart';
import '../../../../../testing/models/room.dart';

void main() {
  late FakeConversation thread;
  late ThreadViewModel viewModel;
  late int closes;
  late int roots;

  setUp(() {
    thread = FakeConversation();
    closes = 0;
    roots = 0;
  });

  Future<void> pump(WidgetTester tester, {MessageItem? root}) async {
    useDesktopSize(tester);
    viewModel = ThreadViewModel(() async => Result.ok(thread));
    addTearDown(viewModel.close);
    unawaited(viewModel.open());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 400,
              child: ThreadPanel(
                room: kTeamRoom,
                rootEventId: '\$root',
                root: root ?? kThreadRoot,
                viewModel: viewModel,
                onClose: () => closes++,
                onGoToRoot: () => roots++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> replies(WidgetTester tester, List<MessageItem> items) async {
    thread.snapshots.add(
      ConversationSnapshot(items: items, reachedStart: true),
    );
    await tester.pump();
    await tester.pump();
  }

  final reply = MessageItem(
    id: 'u1',
    eventId: '\$r1',
    senderId: '@ana:b.c',
    senderName: 'Ana Ribeiro',
    isOwn: false,
    timestamp: DateTime(2026, 10, 4, 10, 51),
    kind: MessageKind.text,
    body: 'Atualizo o changelog.',
    canReply: true,
  );

  testWidgets('cabeçalho, raiz e respostas', (tester) async {
    await pump(tester);
    expect(find.text('Carregando respostas…'), findsOneWidget);
    await replies(tester, [reply]);

    expect(find.text('Thread de Carla'), findsOneWidget);
    expect(find.text('#lançamento-q4'.toUpperCase()), findsOneWidget);
    expect(find.text('Subi a versão final do deck.'), findsOneWidget);
    expect(find.text('4 respostas'), findsOneWidget);
    expect(find.textContaining('Atualizo o changelog.'), findsOneWidget);
    expect(find.text('Responder na thread…'), findsOneWidget);
  });

  testWidgets('thread nova convida a escrever', (tester) async {
    await pump(tester, root: kOtherMessage);
    await replies(tester, []);

    expect(
      find.text('Nenhuma resposta ainda. Escreva a primeira.'),
      findsOneWidget,
    );
  });

  testWidgets('× fecha e a raiz leva à conversa', (tester) async {
    await pump(tester);
    await replies(tester, [reply]);

    await tester.tap(find.byKey(const Key('thread_panel_close')));
    await tester.tap(find.byKey(const Key('thread_panel_root')));

    expect((closes, roots), (1, 1));
  });

  testWidgets('enviar no painel manda para a thread', (tester) async {
    await pump(tester);
    await replies(tester, [reply]);

    await tester.enterText(find.byKey(const Key('message_field')), 'oi');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message_send')));
    await tester.pump();

    expect(thread.sent, ['oi']);
  });

  testWidgets('responder dentro da thread cita a resposta', (tester) async {
    await pump(tester);
    await replies(tester, [reply]);
    viewModel.startReply(reply);
    await tester.pump();

    expect(find.text('Respondendo a Ana Ribeiro'), findsOneWidget);
    expect(find.text('Responder a Ana na thread…'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message_field')), 're');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message_send')));
    await tester.pump();

    expect(thread.sentReplies, [('re', '\$r1')]);
  });

  testWidgets('atualização da thread não repete o aviso de citação ausente', (
    tester,
  ) async {
    await pump(tester);
    MessageItem make(String id, {ReplyPreview? replyTo}) => MessageItem(
      id: id,
      eventId: '\$$id',
      senderId: '@ana:b.c',
      senderName: 'Ana Ribeiro',
      isOwn: false,
      timestamp: DateTime(2026, 10, 4, 10, 51),
      kind: MessageKind.text,
      body: 'Texto $id',
      canReply: true,
      replyTo: replyTo,
    );
    final quoting = make(
      'q1',
      replyTo: const ReplyPreview(
        eventId: '\$sumiu',
        state: ReplyState.unavailable,
      ),
    );
    await replies(tester, [quoting]);
    await tester.tap(find.byKey(const Key('reply_quote_header')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Mensagem fora do histórico carregado'), findsOneWidget);

    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .clearSnackBars();
    await tester.pumpAndSettle();
    expect(find.text('Mensagem fora do histórico carregado'), findsNothing);

    await replies(tester, [quoting, make('q2')]);
    await tester.pump();

    expect(find.text('Mensagem fora do histórico carregado'), findsNothing);
  });
}
