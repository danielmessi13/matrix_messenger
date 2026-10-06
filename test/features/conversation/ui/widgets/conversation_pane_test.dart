import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/conversation/view_models/conversation_view_model.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/conversation_pane.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../../../testing/models/message.dart';
import '../../../../../testing/models/room.dart';

void main() {
  late FakeConversationRepository repository;
  late FakeRoomRepository rooms;

  setUp(() {
    repository = FakeConversationRepository();
    rooms = FakeRoomRepository();
  });

  tearDown(() => rooms.dispose());

  Future<void> pump(
    WidgetTester tester,
    Room? room, {
    Size size = const Size(1440, 900),
  }) async {
    useDesktopSize(tester, size);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ConversationRepository>.value(value: repository),
          RepositoryProvider<RoomRepository>.value(value: rooms),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: ConversationPane(
              room: room,
              now: kDay.add(const Duration(hours: 12)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> show(WidgetTester tester, ConversationSnapshot snapshot) async {
    repository.conversation.snapshots.add(snapshot);
    await tester.pump();
  }

  testWidgets('sem sala selecionada pede para escolher', (tester) async {
    await pump(tester, null);

    expect(find.text('Selecione uma conversa'), findsOneWidget);
    expect(repository.openedRooms, isEmpty);
  });

  testWidgets('abre a conversa da sala e mostra cabeçalho e mensagens', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await show(tester, kSnapshot);

    expect(repository.openedRooms, [kTeamRoom.id]);
    expect(find.text('#lançamento-q4'), findsOneWidget);
    expect(find.text('Hoje, 4 de outubro'), findsOneWidget);
    expect(find.text('Diego Alves'), findsOneWidget);
    expect(find.text('VOCÊ'), findsOneWidget);
    expect(find.text('4 respostas'), findsOneWidget);
  });

  testWidgets('sala vazia', (tester) async {
    await pump(tester, kTeamRoom);
    await show(
      tester,
      const ConversationSnapshot(items: [], reachedStart: true),
    );

    expect(find.text('Nenhuma mensagem ainda.'), findsOneWidget);
  });

  testWidgets('falha ao abrir e tentar de novo', (tester) async {
    repository.openFailure = FakeConversationRepository.notFound;
    await pump(tester, kTeamRoom);

    expect(find.text('Não foi possível abrir a conversa.'), findsOneWidget);
    repository.openFailure = null;
    await tester.tap(find.text('Tentar de novo'));
    await tester.pump();

    expect(repository.openedRooms, [kTeamRoom.id, kTeamRoom.id]);
  });

  testWidgets('convite não abre conversa nem mostra o campo', (tester) async {
    await pump(tester, kInviteRoom);

    expect(find.text('Você foi convidado para esta sala.'), findsOneWidget);
    expect(find.byKey(const Key('message_field')), findsNothing);
    expect(repository.openedRooms, isEmpty);
  });

  testWidgets('aceitar convite mostra indicador e trava os botões', (
    tester,
  ) async {
    rooms.inviteGate = Completer<void>();
    await pump(tester, kInviteRoom);

    await tester.tap(find.byKey(const Key('invite_accept')));
    await tester.pump();

    expect(rooms.accepted, [kInviteRoom.id]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Aceitar'), findsNothing);
    final decline = tester.widget<OutlinedButton>(
      find.byKey(const Key('invite_decline')),
    );
    expect(decline.onPressed, isNull);
    rooms.inviteGate!.complete();
  });

  testWidgets('recusar convite chama o repositório', (tester) async {
    await pump(tester, kInviteRoom);

    await tester.tap(find.byKey(const Key('invite_decline')));
    await tester.pump();

    expect(rooms.declined, [kInviteRoom.id]);
  });

  testWidgets('falha ao responder convite mostra a mensagem', (tester) async {
    rooms.inviteResult = Result.error(Exception('rede'));
    await pump(tester, kInviteRoom);

    await tester.tap(find.byKey(const Key('invite_accept')));
    await tester.pump();

    expect(find.text('Não foi possível responder ao convite.'), findsOneWidget);
    expect(find.text('Aceitar'), findsOneWidget);
  });

  testWidgets('convite aceito vira conversa', (tester) async {
    await pump(tester, kInviteRoom);

    await pump(
      tester,
      Room(id: kInviteRoom.id, name: kInviteRoom.name),
    );

    expect(repository.openedRooms, [kInviteRoom.id]);
    expect(find.byKey(const Key('invite_accept')), findsNothing);
  });

  testWidgets('enviar pelo campo chama a conversa', (tester) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);

    await tester.enterText(find.byKey(const Key('message_field')), 'olá');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message_send')));
    await tester.pump();

    expect(repository.conversation.sent, ['olá']);
  });

  testWidgets('clicar no resumo abre a thread', (tester) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);

    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();

    expect(repository.conversation.openedThreads, ['\$root']);
  });

  testWidgets('início da conversa e indicador de carregamento no topo', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(
      tester,
      ConversationSnapshot(items: kSnapshot.items, reachedStart: true),
    );

    expect(find.text('Início da conversa'), findsOneWidget);
  });

  testWidgets(
    'sem carregar e sem chegar ao início mostra o botão de anteriores',
    (tester) async {
      await pump(tester, kTeamRoom);
      await show(tester, kSnapshot);
      await tester.pump();
      final before = repository.conversation.loadOlderCalls;

      expect(find.byKey(const Key('timeline_loading_older')), findsNothing);
      await tester.tap(find.byKey(const Key('timeline_load_older')));
      await tester.pump();

      expect(repository.conversation.loadOlderCalls, before + 1);
    },
  );

  testWidgets('carregando anteriores mostra o indicador sem o botão', (
    tester,
  ) async {
    final loading = repository.conversation.loadOlderCompleter =
        Completer<void>();
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);
    await tester.pump();

    expect(repository.conversation.loadOlderCalls, 1);
    expect(find.byKey(const Key('timeline_loading_older')), findsOneWidget);
    expect(find.byKey(const Key('timeline_load_older')), findsNothing);
    loading.complete();
    await tester.pump();
  });

  testWidgets('campo desabilitado até a conversa ficar pronta', (tester) async {
    TextField field() =>
        tester.widget<TextField>(find.byKey(const Key('message_field')));
    await pump(tester, kTeamRoom);

    expect(field().enabled, isFalse);
    await show(tester, kSnapshot);

    expect(field().enabled, isTrue);
  });

  testWidgets('rolar até o topo pede mensagens antigas', (tester) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    await show(
      tester,
      ConversationSnapshot(
        items: [
          for (var i = 0; i < 30; i++)
            MessageItem(
              id: '\$m$i',
              senderId: '@bob:b.c',
              senderName: 'Bob',
              isOwn: false,
              timestamp: kDay.add(Duration(minutes: i)),
              kind: MessageKind.text,
              body: 'mensagem $i',
            ),
        ],
        reachedStart: false,
      ),
    );

    await tester.drag(
      find.byKey(const Key('timeline_list')),
      const Offset(0, 5000),
    );
    await tester.pump();

    expect(repository.conversation.loadOlderCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('mensagem nova lendo mais acima mostra o botão de recentes', (
    tester,
  ) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    final many = [
      for (var i = 0; i < 30; i++)
        MessageItem(
          id: '\$m$i',
          senderId: '@bob:b.c',
          senderName: 'Bob',
          isOwn: false,
          timestamp: kDay.add(Duration(minutes: i)),
          kind: MessageKind.text,
          body: 'mensagem $i',
        ),
    ];
    await show(tester, ConversationSnapshot(items: many, reachedStart: true));

    await tester.drag(
      find.byKey(const Key('timeline_list')),
      const Offset(0, 800),
    );
    await tester.pump();
    await show(
      tester,
      ConversationSnapshot(items: [...many, kOtherMessage], reachedStart: true),
    );

    expect(find.byKey(const Key('jump_to_latest')), findsOneWidget);
    await tester.tap(find.byKey(const Key('jump_to_latest')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('jump_to_latest')), findsNothing);
  });

  MessageItem msg(
    int i, {
    bool own = false,
    SendState state = SendState.sent,
    String? id,
  }) => MessageItem(
    id: id ?? '\$m$i',
    senderId: own ? '@alice:matrix.org' : '@bob:b.c',
    senderName: own ? 'Alice' : 'Bob',
    isOwn: own,
    timestamp: kDay.add(Duration(minutes: i)),
    kind: MessageKind.text,
    body: 'mensagem $i',
    sendState: state,
  );

  testWidgets('timeline que esvazia e volta com mensagem nova não quebra', (
    tester,
  ) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    final many = [for (var i = 0; i < 30; i++) msg(i)];
    await show(tester, ConversationSnapshot(items: many, reachedStart: true));
    await tester.drag(
      find.byKey(const Key('timeline_list')),
      const Offset(0, 800),
    );
    await tester.pump();

    await show(
      tester,
      const ConversationSnapshot(items: [], reachedStart: true),
    );
    expect(find.text('Nenhuma mensagem ainda.'), findsOneWidget);

    await show(
      tester,
      ConversationSnapshot(items: [msg(99)], reachedStart: true),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('mensagem 99'), findsOneWidget);
    expect(find.byKey(const Key('jump_to_latest')), findsNothing);
  });

  testWidgets(
    'mensagem nova com a leitura mais acima não move o conteúdo visível',
    (tester) async {
      await pump(tester, kTeamRoom, size: const Size(1440, 500));
      final many = [for (var i = 0; i < 30; i++) msg(i)];
      await show(tester, ConversationSnapshot(items: many, reachedStart: true));
      await tester.drag(
        find.byKey(const Key('timeline_list')),
        const Offset(0, 800),
      );
      await tester.pump();
      final before = tester.getTopLeft(find.byKey(const Key('message_\$m20')));

      await show(
        tester,
        ConversationSnapshot(items: [...many, msg(99)], reachedStart: true),
      );
      await tester.pump();

      final after = tester.getTopLeft(find.byKey(const Key('message_\$m20')));
      expect((after.dy - before.dy).abs(), lessThanOrEqualTo(1));
    },
  );

  testWidgets(
    'histórico curto sem chegar ao início pede mensagens antigas sem rolar',
    (tester) async {
      await pump(tester, kTeamRoom);
      await show(
        tester,
        ConversationSnapshot(items: [msg(1), msg(2)], reachedStart: false),
      );
      await tester.pump();

      expect(repository.conversation.loadOlderCalls, greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    'mudança de estado da última mensagem não mostra o botão de recentes',
    (tester) async {
      await pump(tester, kTeamRoom, size: const Size(1440, 500));
      final many = [
        for (var i = 0; i < 29; i++) msg(i),
        msg(29, own: true, id: 'txn', state: SendState.sending),
      ];
      await show(tester, ConversationSnapshot(items: many, reachedStart: true));
      await tester.drag(
        find.byKey(const Key('timeline_list')),
        const Offset(0, 800),
      );
      await tester.pump();

      final sent = [...many.take(29), msg(29, own: true, id: 'txn')];
      await show(tester, ConversationSnapshot(items: sent, reachedStart: true));
      await tester.pump();

      expect(find.byKey(const Key('jump_to_latest')), findsNothing);
    },
  );

  testWidgets('mensagem própria nova com a leitura mais acima rola até o fim', (
    tester,
  ) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    final many = [for (var i = 0; i < 30; i++) msg(i)];
    await show(tester, ConversationSnapshot(items: many, reachedStart: true));
    await tester.drag(
      find.byKey(const Key('timeline_list')),
      const Offset(0, 800),
    );
    await tester.pump();

    await show(
      tester,
      ConversationSnapshot(
        items: [
          ...many,
          msg(99, own: true, state: SendState.sending),
        ],
        reachedStart: true,
      ),
    );
    await tester.pumpAndSettle();

    final list = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('timeline_list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(list.position.pixels, 0);
    expect(find.byKey(const Key('jump_to_latest')), findsNothing);
  });

  testWidgets(
    'mensagem própria vinda de outro aparelho não tira a leitura do lugar',
    (tester) async {
      await pump(tester, kTeamRoom, size: const Size(1440, 500));
      final many = [for (var i = 0; i < 30; i++) msg(i)];
      await show(tester, ConversationSnapshot(items: many, reachedStart: true));
      await tester.drag(
        find.byKey(const Key('timeline_list')),
        const Offset(0, 800),
      );
      await tester.pump();

      await show(
        tester,
        ConversationSnapshot(
          items: [...many, msg(99, own: true)],
          reachedStart: true,
        ),
      );
      await tester.pumpAndSettle();

      final list = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('timeline_list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(list.position.pixels, greaterThan(0));
      expect(find.byKey(const Key('jump_to_latest')), findsOneWidget);
    },
  );

  testWidgets(
    'indicador de carregamento aparece no topo quando há mais histórico',
    (tester) async {
      final loading = repository.conversation.loadOlderCompleter =
          Completer<void>();
      await pump(tester, kTeamRoom, size: const Size(1440, 500));
      await show(
        tester,
        ConversationSnapshot(
          items: [for (var i = 0; i < 30; i++) msg(i)],
          reachedStart: false,
        ),
      );
      await tester.drag(
        find.byKey(const Key('timeline_list')),
        const Offset(0, 5000),
      );
      await tester.pump();

      expect(find.byKey(const Key('timeline_loading_older')), findsOneWidget);
      loading.complete();
      await tester.pump();
    },
  );

  testWidgets(
    'falha ao pedir mensagens antigas não gera novas tentativas sozinha',
    (tester) async {
      repository.conversation.loadOlderResult = const Result.error(
        FakeConversationRepository.notFound,
      );
      await pump(tester, kTeamRoom);
      await show(
        tester,
        ConversationSnapshot(items: [msg(1), msg(2)], reachedStart: false),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(repository.conversation.loadOlderCalls, 1);
    },
  );

  testWidgets(
    'itens que chegam durante o carregamento antigo continuam a paginação',
    (tester) async {
      final completer = Completer<void>();
      repository.conversation.loadOlderCompleter = completer;
      repository.conversation.loadOlderResult = const Result.ok(false);
      await pump(tester, kTeamRoom);
      await show(
        tester,
        ConversationSnapshot(items: [msg(1), msg(2)], reachedStart: false),
      );
      await tester.pump();
      expect(repository.conversation.loadOlderCalls, 1);

      await show(
        tester,
        ConversationSnapshot(
          items: [msg(0), msg(1), msg(2)],
          reachedStart: false,
        ),
      );
      await tester.pump();
      completer.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(repository.conversation.loadOlderCalls, 2);
    },
  );

  testWidgets('texto longo sem espaços e nome longo a 1024 px não estouram', (
    tester,
  ) async {
    await pump(tester, kTeamRoom, size: const Size(1024, 640));
    await show(
      tester,
      ConversationSnapshot(
        items: [
          MessageItem(
            id: '\$long',
            senderId: '@x:b.c',
            senderName:
                'Alguém Com Um Nome Muito Muito Muito Muito Muito Longo Mesmo',
            isOwn: false,
            timestamp: kDay,
            kind: MessageKind.text,
            body: 'a' * 600,
          ),
          MessageItem(
            id: 'txn',
            senderId: '@alice:matrix.org',
            senderName: 'Alice',
            isOwn: true,
            timestamp: kDay,
            kind: MessageKind.text,
            body: 'b' * 600,
            sendState: SendState.failed,
          ),
        ],
        reachedStart: true,
      ),
    );

    expect(tester.takeException(), isNull);
  });

  Future<void> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump();
  }

  MessageItem bob(int i, {ReplyPreview? replyTo}) => MessageItem(
    id: 'u$i',
    eventId: '\$m$i',
    senderId: '@bob:b.c',
    senderName: 'Bob Souza',
    isOwn: false,
    timestamp: kDay.add(Duration(minutes: i)),
    kind: MessageKind.text,
    body: 'mensagem $i',
    canReply: true,
    replyTo: replyTo,
  );

  testWidgets('Responder pelo hover mostra a barra e envia citando', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);

    await hover(tester, find.textContaining('A integração'));
    await tester.tap(find.byKey(const Key('message_reply_\$other')));
    await tester.pump();

    expect(find.text('Respondendo a Diego Alves'), findsOneWidget);
    expect(find.text('Responder a Diego…'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message_field')), 're');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message_send')));
    await tester.pump();

    expect(repository.conversation.sentReplies, [('re', '\$other')]);
    expect(find.byKey(const Key('reply_bar')), findsNothing);
  });

  testWidgets('Thread pelo hover abre a thread da mensagem', (tester) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);

    await hover(tester, find.textContaining('A integração'));
    await tester.tap(find.byKey(const Key('message_thread_\$other')));
    await tester.pump();
    await tester.pump();

    expect(repository.conversation.openedThreads, ['\$other']);
    expect(find.text('Vendo no painel'), findsOneWidget);
  });

  testWidgets('a raiz de uma thread não oferece Thread no hover', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);

    await hover(tester, find.textContaining('Subi a versão'));

    expect(find.byKey(const Key('message_reply_\$root')), findsOneWidget);
    expect(find.byKey(const Key('message_thread_\$root')), findsNothing);
  });

  testWidgets('clicar na citação rola até a original', (tester) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    await show(
      tester,
      ConversationSnapshot(
        items: [
          for (var i = 0; i < 29; i++) bob(i),
          bob(
            29,
            replyTo: const ReplyPreview(
              eventId: '\$m0',
              state: ReplyState.ready,
              senderName: 'Bob Souza',
              body: 'mensagem 0',
            ),
          ),
        ],
        reachedStart: true,
      ),
    );
    final first = find.text('mensagem 0');
    expect(tester.getRect(first).top, lessThan(0));

    await tester.tap(find.byKey(const Key('reply_quote_header')));
    await tester.pumpAndSettle();

    expect(tester.getRect(first).top, greaterThanOrEqualTo(0));
  });

  testWidgets('citação fora do histórico avisa', (tester) async {
    await pump(tester, kTeamRoom);
    await show(
      tester,
      ConversationSnapshot(
        items: [
          bob(
            1,
            replyTo: const ReplyPreview(
              eventId: '\$sumiu',
              state: ReplyState.unavailable,
            ),
          ),
        ],
        reachedStart: true,
      ),
    );

    await tester.tap(find.byKey(const Key('reply_quote_header')));
    await tester.pumpAndSettle();

    expect(find.text('Mensagem fora do histórico carregado'), findsOneWidget);
  });

  testWidgets('resposta a mim lendo mais acima mostra o aviso', (
    tester,
  ) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    final items = [for (var i = 0; i < 30; i++) bob(i)];
    await show(tester, ConversationSnapshot(items: items, reachedStart: true));
    await tester.drag(
      find.byKey(const Key('timeline_list')),
      const Offset(0, 600),
    );
    await tester.pump();

    await show(
      tester,
      ConversationSnapshot(
        items: [
          ...items,
          bob(
            30,
            replyTo: const ReplyPreview(
              eventId: '\$own',
              state: ReplyState.ready,
              isOwn: true,
            ),
          ),
        ],
        reachedStart: true,
      ),
    );
    await tester.pump();

    expect(find.text('↩ Bob Souza respondeu a você · Ver'), findsOneWidget);
    expect(find.byKey(const Key('jump_to_latest')), findsNothing);
    await tester.tap(find.byKey(const Key('reply_notice_dismiss')));
    await tester.pump();

    expect(find.byKey(const Key('reply_notice')), findsNothing);
    expect(find.byKey(const Key('jump_to_latest')), findsOneWidget);
  });

  testWidgets('citação que carrega depois e é minha mostra o aviso', (
    tester,
  ) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    final items = [for (var i = 0; i < 30; i++) bob(i)];
    await show(tester, ConversationSnapshot(items: items, reachedStart: true));
    await tester.drag(
      find.byKey(const Key('timeline_list')),
      const Offset(0, 600),
    );
    await tester.pump();
    await show(
      tester,
      ConversationSnapshot(
        items: [
          ...items,
          bob(
            30,
            replyTo: const ReplyPreview(
              eventId: '\$own',
              state: ReplyState.loading,
            ),
          ),
        ],
        reachedStart: true,
      ),
    );
    expect(find.byKey(const Key('reply_notice')), findsNothing);

    await show(
      tester,
      ConversationSnapshot(
        items: [
          ...items,
          bob(
            30,
            replyTo: const ReplyPreview(
              eventId: '\$own',
              state: ReplyState.ready,
              isOwn: true,
            ),
          ),
        ],
        reachedStart: true,
      ),
    );
    await tester.pump();

    expect(find.text('↩ Bob Souza respondeu a você · Ver'), findsOneWidget);
  });

  testWidgets('abrir a thread mostra o painel e × fecha', (tester) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);

    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('thread_panel')), findsOneWidget);
    expect(find.text('Thread de Carla'), findsOneWidget);
    await tester.tap(find.byKey(const Key('thread_panel_close')));
    await tester.pump();

    expect(find.byKey(const Key('thread_panel')), findsNothing);
  });

  testWidgets('Esc cancela a resposta e depois fecha o painel', (tester) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);
    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();
    await hover(tester, find.textContaining('A integração'));
    await tester.tap(find.byKey(const Key('message_reply_\$other')));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('reply_bar')), findsNothing);
    expect(find.byKey(const Key('thread_panel')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byKey(const Key('thread_panel')), findsNothing);
  });

  testWidgets('fechar o painel com Esc devolve o foco ao campo da conversa', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);
    final threadConversation = FakeConversation();
    repository.conversation.threadResult = Result.ok(threadConversation);
    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();
    threadConversation.snapshots.add(
      const ConversationSnapshot(items: [], reachedStart: true),
    );
    await tester.pump();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('thread_panel')), findsNothing);
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('message_field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('painel com a janela a 1024 px não estoura', (tester) async {
    await pump(tester, kTeamRoom, size: const Size(1024, 640));
    await show(tester, kSnapshot);

    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('thread_panel')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('thread_panel'))).width, 400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('abrir e fechar a thread preserva o rascunho da conversa', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);
    await tester.enterText(find.byKey(const Key('message_field')), 'rascunho');
    await tester.pump();

    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('thread_panel_close')));
    await tester.pump();

    expect(find.text('rascunho'), findsOneWidget);
  });

  testWidgets('abrir a thread preserva a rolagem da conversa', (tester) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    final many = [
      for (var i = 0; i < 30; i++)
        MessageItem(
          id: 'm$i',
          eventId: '\$m$i',
          senderId: '@bob:b.c',
          senderName: 'Bob',
          isOwn: false,
          timestamp: kDay.add(Duration(minutes: i)),
          kind: MessageKind.text,
          body: 'mensagem $i',
        ),
      kThreadRoot,
    ];
    await show(tester, ConversationSnapshot(items: many, reachedStart: true));
    await tester.drag(
      find.byKey(const Key('timeline_list')),
      const Offset(0, 800),
    );
    await tester.pump();
    final scrollable = find.descendant(
      of: find.byKey(const Key('timeline_list')),
      matching: find.byType(Scrollable),
    );
    final before = tester
        .state<ScrollableState>(scrollable.first)
        .position
        .pixels;
    tester
        .element(find.byKey(const Key('timeline_list')))
        .read<ConversationViewModel>()
        .openThread('\$root');
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('thread_panel')), findsOneWidget);
    expect(
      tester.state<ScrollableState>(scrollable.first).position.pixels,
      before,
    );
  });

  testWidgets('abrir a thread move o foco para o campo do painel', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);
    final threadConversation = FakeConversation();
    repository.conversation.threadResult = Result.ok(threadConversation);
    await tester.tap(find.byKey(const Key('message_field')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();
    threadConversation.snapshots.add(
      const ConversationSnapshot(items: [], reachedStart: true),
    );
    await tester.pump();
    await tester.pump();

    final field = find.descendant(
      of: find.byKey(const Key('thread_panel')),
      matching: find.byKey(const Key('message_field')),
    );
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasPrimaryFocus, isTrue);
  });

  testWidgets('a 900 px o painel fica por cima da conversa', (tester) async {
    await pump(tester, kTeamRoom, size: const Size(900, 640));
    await show(tester, kSnapshot);

    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();

    expect(tester.getSize(find.byKey(const Key('thread_panel'))).width, 400);
    expect(tester.getSize(find.byKey(const Key('timeline_list'))).width, 900);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a 380 px o painel ocupa a largura da janela', (tester) async {
    await pump(tester, kTeamRoom, size: const Size(380, 640));
    await show(tester, kSnapshot);
    // O cabeçalho da conversa já estoura abaixo da largura mínima, sem relação com o painel.
    tester.takeException();

    await tester.tap(
      find.byKey(const Key('thread_toggle_\$root')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump();

    expect(tester.getSize(find.byKey(const Key('thread_panel'))).width, 380);
    expect(tester.takeException(), isNull);
  });
}
