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
import 'package:matrix_messenger/features/conversation/ui/widgets/message_labels.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/thread_request.dart';

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
    ThreadRequest? threadRequest,
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
              threadRequest: threadRequest,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('pedido de thread abre a thread, também com a sala já aberta', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    expect(repository.conversation.openedThreads, isEmpty);

    final request = ThreadRequest(roomId: kTeamRoom.id, rootEventId: r'$raiz');
    await pump(tester, kTeamRoom, threadRequest: request);
    await pump(tester, kTeamRoom, threadRequest: request);

    expect(repository.conversation.openedThreads, [r'$raiz']);
    expect(repository.openedRooms, [kTeamRoom.id]);

    await pump(
      tester,
      kTeamRoom,
      threadRequest: ThreadRequest(roomId: kTeamRoom.id, rootEventId: r'$raiz'),
    );
    // Pedido novo para a thread já aberta não reabre (openThread ignora a mesma raiz).
    expect(repository.conversation.openedThreads, [r'$raiz']);
  });

  testWidgets('pedido de thread de outra sala é ignorado', (tester) async {
    await pump(
      tester,
      kTeamRoom,
      threadRequest: ThreadRequest(roomId: kDirectRoom.id, rootEventId: r'$x'),
    );

    expect(repository.conversation.openedThreads, isEmpty);
  });

  // Dois pumps: na abertura nada anima, e o frame do novo estado só sai no seguinte.
  Future<void> show(WidgetTester tester, ConversationSnapshot snapshot) async {
    repository.conversation.snapshots.add(snapshot);
    await tester.pump();
    await tester.pump();
  }

  ConversationSnapshot page(
    List<TimelineItem> items, {
    bool reachedStart = false,
    bool paginating = false,
  }) => ConversationSnapshot(
    items: items,
    reachedStart: reachedStart,
    paginating: paginating,
  );

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

  testWidgets('sem sala selecionada pede para escolher', (tester) async {
    await pump(tester, null);

    expect(find.text('Selecione uma conversa'), findsOneWidget);
    expect(repository.openedRooms, isEmpty);
  });

  testWidgets('abre a conversa da sala e mostra cabeçalho e mensagens', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await show(tester, kSnapshot);

    expect(repository.openedRooms, [kTeamRoom.id]);
    expect(find.text('#lançamento-q4'), findsOneWidget);
    expect(find.text('Hoje, 4 de outubro'), findsOneWidget);
    expect(find.text('Diego Alves'), findsOneWidget);
    expect(find.text('Você'), findsOneWidget);
    expect(find.text('4 respostas'), findsOneWidget);
  });

  testWidgets('uma mensagem só fica embaixo, junto do campo', (tester) async {
    await pump(tester, kTeamRoom);
    await show(
      tester,
      ConversationSnapshot(items: [kOtherMessage], reachedStart: true),
    );

    final message = tester.getRect(find.textContaining('A integração'));
    final field = tester.getRect(find.byKey(const Key('message_field')));
    expect(field.top - message.bottom, lessThan(120));
  });

  testWidgets('abertura rápida não pisca o carregamento', (tester) async {
    await pump(tester, kTeamRoom);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await show(tester, kSnapshot);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Diego Alves'), findsOneWidget);
  });

  testWidgets('abertura demorada mostra o carregamento', (tester) async {
    await pump(tester, kTeamRoom);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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

  testWidgets('no início mostra "Início da conversa" e não busca', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(tester, page(kSnapshot.items, reachedStart: true));

    expect(find.text('Início da conversa'), findsOneWidget);
    expect(find.byKey(const Key('timeline_load_older')), findsNothing);
    expect(repository.conversation.loadOlderCalls, 0);
  });

  // Página sem nada visível não muda o estado; a tela pede de novo até o início.
  void reachStartOnCall(int call) {
    final conversation = repository.conversation
      ..loadOlderResult = const Result.ok(false);
    conversation.onLoadOlder = () {
      if (conversation.loadOlderCalls == call) {
        conversation.loadOlderResult = const Result.ok(true);
      }
    };
  }

  testWidgets('lista curta parada pede anteriores até o início', (
    tester,
  ) async {
    reachStartOnCall(2);
    await pump(tester, kTeamRoom);
    await show(tester, page(kSnapshot.items));
    await tester.pump();

    expect(repository.conversation.loadOlderCalls, 2);
    expect(find.text('Início da conversa'), findsOneWidget);
    expect(find.byKey(const Key('timeline_load_older')), findsNothing);
  });

  testWidgets('lista vazia sem início mostra o carregamento e pede uma vez', (
    tester,
  ) async {
    final pending = repository.conversation.loadOlderCompleter =
        Completer<void>();
    await pump(tester, kTeamRoom);
    await show(tester, page(const []));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('timeline_loading_center')), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const Key('timeline_loading_center')), findsOneWidget);
    expect(find.byKey(const Key('timeline_loading_older')), findsNothing);
    expect(repository.conversation.loadOlderCalls, 1);
    pending.complete();
    await tester.pump();
  });

  testWidgets('lista vazia pede de novo sem snapshot novo até o início', (
    tester,
  ) async {
    reachStartOnCall(3);
    await pump(tester, kTeamRoom);
    await show(tester, page(const []));
    await tester.pump();

    expect(repository.conversation.loadOlderCalls, 3);
    expect(find.text('Nenhuma mensagem ainda.'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(repository.conversation.loadOlderCalls, 3);
  });

  testWidgets('paginando com a lista curta não mostra spinner nem botão', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(tester, page(kSnapshot.items, paginating: true));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('timeline_loading_older')), findsNothing);
    expect(find.byKey(const Key('timeline_load_older')), findsNothing);
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
    await show(tester, page([for (var i = 0; i < 30; i++) msg(i)]));
    expect(repository.conversation.loadOlderCalls, 0);

    // O primeiro arraste revela as 10 escondidas; o segundo chega ao topo sem nada escondido.
    for (var i = 0; i < 2; i++) {
      await tester.drag(
        find.byKey(const Key('timeline_list')),
        const Offset(0, 5000),
      );
      await tester.pump();
    }

    expect(repository.conversation.loadOlderCalls, 1);
  });

  testWidgets('subir revela as mensagens já carregadas sem pedir ao Rust', (
    tester,
  ) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    await show(
      tester,
      page([for (var i = 0; i < 60; i++) msg(i)], reachedStart: true),
    );
    expect(find.text('mensagem 39'), findsNothing);
    expect(find.text('Início da conversa'), findsNothing);

    await tester.drag(
      find.byKey(const Key('timeline_list')),
      const Offset(0, 5000),
    );
    await tester.pump();

    expect(find.text('mensagem 39'), findsOneWidget);
    expect(repository.conversation.loadOlderCalls, 0);
  });

  testWidgets('um passo da roda perto do topo revela uma vez, não tudo', (
    tester,
  ) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    await show(
      tester,
      page([for (var i = 0; i < 120; i++) msg(i)], reachedStart: true),
    );
    final list = find.byKey(const Key('timeline_list'));
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    final thumbBefore =
        (position.maxScrollExtent - position.viewportDimension * 2 + 10) /
        position.maxScrollExtent;

    position.jumpTo(
      position.maxScrollExtent - position.viewportDimension * 2 + 10,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('mensagem 80'), findsOneWidget);
    expect(find.text('mensagem 0'), findsNothing);
    expect(
      position.pixels / position.maxScrollExtent,
      greaterThan(thumbBefore / 3),
    );
  });

  testWidgets('pede mais a duas alturas da área visível do topo', (
    tester,
  ) async {
    await pump(tester, kTeamRoom, size: const Size(1440, 524));
    await show(tester, page([for (var i = 0; i < 60; i++) msg(i)]));
    final position = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(const Key('timeline_list')),
            matching: find.byType(Scrollable),
          ),
        )
        .position;
    final distance = position.viewportDimension * 2 - 20;
    expect(distance, greaterThan(400));

    position.jumpTo(position.maxScrollExtent - distance);
    await tester.pump();

    expect(find.text('mensagem 39'), findsOneWidget);
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

  testWidgets('paginando com a lista que já rola mostra o spinner no topo', (
    tester,
  ) async {
    final many = [for (var i = 0; i < 30; i++) msg(i)];
    await pump(tester, kTeamRoom, size: const Size(1440, 500));
    await show(tester, page(many));
    await tester.drag(
      find.byKey(const Key('timeline_list')),
      const Offset(0, 5000),
    );
    await tester.pump();
    await show(tester, page(many, paginating: true));
    expect(find.byKey(const Key('timeline_loading_older')), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('timeline_loading_older')), findsOneWidget);
    expect(find.byKey(const Key('timeline_load_older')), findsNothing);
  });

  testWidgets('falha com a lista vazia mostra o botão no centro', (
    tester,
  ) async {
    repository.conversation.loadOlderResult = const Result.error(
      FakeConversationRepository.notFound,
    );
    await pump(tester, kTeamRoom);
    await show(tester, page(const []));
    await tester.pump();

    final button = find.byKey(const Key('timeline_load_older'));
    expect(button, findsOneWidget);
    expect(find.byKey(const Key('timeline_loading_center')), findsNothing);
    final center = tester.getCenter(find.byKey(const Key('timeline_list')));
    expect((tester.getCenter(button).dy - center.dy).abs(), lessThan(40));
  });

  testWidgets('falha mostra o botão e só ele pede de novo', (tester) async {
    repository.conversation.loadOlderResult = const Result.error(
      FakeConversationRepository.notFound,
    );
    await pump(tester, kTeamRoom);
    await show(tester, page([msg(1), msg(2)]));
    expect(repository.conversation.loadOlderCalls, 1);
    await tester.pump();

    expect(find.byKey(const Key('timeline_load_older')), findsOneWidget);
    await show(tester, page([msg(1), msg(2), msg(3)]));
    await show(tester, page([msg(1), msg(2), msg(3)], paginating: true));
    await show(tester, page([msg(1), msg(2), msg(3)]));
    expect(repository.conversation.loadOlderCalls, 1);

    await tester.tap(find.byKey(const Key('timeline_load_older')));
    await tester.pump();

    expect(repository.conversation.loadOlderCalls, 2);
  });

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
    // A citação também mostra "mensagem 0"; vale só a mensagem original.
    final first = find.byKey(const Key('message_u0'));
    expect(first, findsNothing);

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

    expect(find.text('Bob Souza respondeu a você · Ver'), findsOneWidget);
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

    expect(find.text('Bob Souza respondeu a você · Ver'), findsOneWidget);
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

  testWidgets(
    'sala só com eventos ocultos carrega até o início e mostra o estado vazio',
    (tester) async {
      reachStartOnCall(4);
      final first = repository.conversation.loadOlderCompleter =
          Completer<void>();
      await pump(tester, kTeamRoom);
      await show(tester, page(const []));
      await show(tester, page(const [], paginating: true));
      first.complete();
      await tester.pump();
      expect(repository.conversation.loadOlderCalls, 1);

      await show(tester, page(const []));
      await show(tester, page(const [], reachedStart: true));

      expect(repository.conversation.loadOlderCalls, 4);
      expect(find.text('Nenhuma mensagem ainda.'), findsOneWidget);
      expect(find.byKey(const Key('timeline_loading_center')), findsNothing);
      expect(find.byKey(const Key('timeline_load_older')), findsNothing);
    },
  );

  testWidgets('mensagens seguidas do mesmo autor mostram o nome uma vez', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(
      tester,
      page([
        DateDividerItem(kDay),
        msg(0),
        msg(1),
        msg(10),
      ], reachedStart: true),
    );

    expect(find.text('Bob'), findsNWidgets(2));
    final first = tester.getRect(find.text('mensagem 0'));
    final second = tester.getRect(find.text('mensagem 1'));
    expect(second.top - first.bottom, lessThan(12));
  });

  testWidgets('evento de sala aparece numa linha e quebra o grupo', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(
      tester,
      page([
        DateDividerItem(kDay),
        msg(0),
        RoomEventItem(
          id: '\$join',
          senderName: 'Ana',
          isOwn: false,
          timestamp: kDay.add(const Duration(minutes: 1)),
          kind: RoomEventKind.joined,
        ),
        msg(2),
      ], reachedStart: true),
    );

    expect(find.byKey(const Key('room_event_\$join')), findsOneWidget);
    expect(find.textContaining('Ana entrou na sala'), findsOneWidget);
    expect(find.text('Bob'), findsNWidgets(2));
  });

  testWidgets('sala só com eventos mostra as linhas, não o estado vazio', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(
      tester,
      page([
        RoomEventItem(
          id: '\$create',
          senderName: 'Bob',
          isOwn: true,
          timestamp: kDay,
          kind: RoomEventKind.created,
        ),
      ], reachedStart: true),
    );

    expect(find.byKey(const Key('room_event_\$create')), findsOneWidget);
    expect(find.textContaining('Você criou a sala'), findsOneWidget);
    expect(find.text('Nenhuma mensagem ainda.'), findsNothing);
  });

  testWidgets('minhas mensagens seguidas formam um grupo com status no fim', (
    tester,
  ) async {
    await pump(tester, kTeamRoom);
    await show(
      tester,
      page([
        DateDividerItem(kDay),
        msg(0, own: true, id: r'$a'),
        msg(0, own: true, id: r'$b'),
        msg(0, own: true, id: r'$c'),
      ], reachedStart: true),
    );

    expect(find.text('Você'), findsOneWidget);
    expect(find.text('Enviada'), findsOneWidget);
    final a = tester.getRect(find.byKey(const Key(r'message_$a')));
    final b = tester.getRect(find.byKey(const Key(r'message_$b')));
    final c = tester.getRect(find.byKey(const Key(r'message_$c')));
    expect(b.top, a.bottom);
    expect(c.top, b.bottom);
    expect(
      tester.getTopLeft(find.text('Enviada')).dy,
      greaterThan(tester.getTopLeft(find.text('mensagem 0').last).dy),
    );
  });

  group('evento de sala com texto longo', () {
    RoomEventItem topic(String value) => RoomEventItem(
      id: r'$topic',
      senderName: 'Daniel Messias',
      isOwn: false,
      timestamp: kDay.add(const Duration(hours: 2, minutes: 6)),
      kind: RoomEventKind.topicChanged,
      value: value,
    );

    Future<Rect> showTopic(WidgetTester tester, String value) async {
      await pump(tester, kTeamRoom);
      await show(tester, page([topic(value)], reachedStart: true));
      expect(tester.takeException(), isNull);
      return tester.getRect(
        find
            .descendant(
              of: find.byKey(const Key(r'room_event_$topic')),
              matching: find.byType(RichText),
            )
            .first,
      );
    }

    void expectCenteredAndWrapped(WidgetTester tester, Rect text) {
      final list = tester.getRect(find.byKey(const Key('timeline_list')));
      expect(text.width, lessThanOrEqualTo(560));
      expect(text.center.dx, closeTo(list.center.dx, 1));
      final icon = tester.getRect(find.byIcon(Icons.notes));
      expect(icon.left, greaterThanOrEqualTo(text.left));
      expect(text.height, greaterThan(icon.height * 2));
    }

    testWidgets('fica centralizado e a hora segue o texto', (tester) async {
      final text = await showTopic(tester, 'palavra ' * 40);

      expectCenteredAndWrapped(tester, text);
      final line = tester.widget<RichText>(
        find
            .descendant(
              of: find.byKey(const Key(r'room_event_$topic')),
              matching: find.byType(RichText),
            )
            .first,
      );
      expect(
        line.text.toPlainText(),
        endsWith('”\u00A0\u00A0${formatMessageTime(topic('').timestamp)}'),
      );
    });

    testWidgets('tópico sem espaços quebra dentro do bloco', (tester) async {
      final text = await showTopic(tester, 'asd' * 60);

      expectCenteredAndWrapped(tester, text);
    });
  });

  group('eventos de sala seguidos', () {
    RoomEventItem topic(int i) => RoomEventItem(
      id: '\$t$i',
      senderName: 'Daniel Messias',
      isOwn: false,
      timestamp: kDay.add(Duration(minutes: 10 + i)),
      kind: RoomEventKind.topicChanged,
      value: 'tópico $i',
    );

    final events = [for (var i = 0; i < 3; i++) topic(i)];
    const summary = Key(r'room_event_group_$t0');
    const collapse = Key(r'room_event_group_collapse_$t0');

    testWidgets('começam recolhidos num resumo com a hora do último', (
      tester,
    ) async {
      await pump(tester, kTeamRoom);
      await show(tester, page([msg(0), ...events, msg(20)]));

      expect(find.byKey(summary), findsOneWidget);
      expect(
        find.textContaining(
          'Daniel Messias mudou o tópico 3 vezes'
          '\u00A0\u00A0${formatMessageTime(events.last.timestamp)}',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key(r'room_event_$t0')), findsNothing);
      expect(find.text('Bob'), findsNWidgets(2));
    });

    testWidgets('expandir mostra cada evento e Recolher volta ao resumo', (
      tester,
    ) async {
      await pump(tester, kTeamRoom);
      await show(tester, page([msg(0), ...events, msg(20)]));

      await tester.tap(find.byKey(summary));
      await tester.pump();

      for (final e in events) {
        expect(find.byKey(Key('room_event_${e.id}')), findsOneWidget);
      }
      expect(find.byKey(summary), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(collapse)).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(const Key(r'room_event_$t2'))).dy,
        ),
      );

      await tester.tap(find.byKey(collapse));
      await tester.pump();

      expect(find.byKey(summary), findsOneWidget);
      expect(find.byKey(const Key(r'room_event_$t0')), findsNothing);
    });

    testWidgets('evento novo no fim mantém o grupo aberto', (tester) async {
      await pump(tester, kTeamRoom);
      await show(tester, page([msg(0), ...events]));
      await tester.tap(find.byKey(summary));
      await tester.pump();

      await show(tester, page([msg(0), ...events, topic(3)]));

      expect(find.byKey(const Key(r'room_event_$t3')), findsOneWidget);
      expect(find.byKey(collapse), findsOneWidget);
    });

    testWidgets('evento antigo no começo mantém o grupo aberto', (
      tester,
    ) async {
      await pump(tester, kTeamRoom);
      await show(tester, page([...events, msg(20)]));
      await tester.tap(find.byKey(summary));
      await tester.pump();

      final older = RoomEventItem(
        id: r'$antes',
        senderName: 'Daniel Messias',
        isOwn: false,
        timestamp: kDay.add(const Duration(minutes: 5)),
        kind: RoomEventKind.topicChanged,
        value: 'tópico antigo',
      );
      await show(tester, page([older, ...events, msg(20)]));

      expect(find.byKey(const Key(r'room_event_$antes')), findsOneWidget);
      expect(
        find.byKey(const Key(r'room_event_group_collapse_$antes')),
        findsOneWidget,
      );
    });

    testWidgets('expandir lendo mais acima não move o que está embaixo', (
      tester,
    ) async {
      await pump(tester, kTeamRoom, size: const Size(1440, 500));
      await show(
        tester,
        page([
          for (var i = 0; i < 10; i++) msg(i),
          ...events,
          for (var i = 20; i < 40; i++) msg(i),
        ], reachedStart: true),
      );
      await tester.dragUntilVisible(
        find.byKey(summary),
        find.byKey(const Key('timeline_list')),
        const Offset(0, 200),
      );
      await tester.pump();
      final below = find.text('mensagem 20');
      final before = tester.getTopLeft(below).dy;
      final summaryBottom = tester.getBottomLeft(find.byKey(summary)).dy;

      await tester.tap(find.byKey(summary));
      await tester.pump();

      expect(tester.getTopLeft(below).dy, before);
      expect(
        tester.getBottomLeft(find.byKey(collapse)).dy,
        closeTo(summaryBottom, 1),
      );
    });

    testWidgets('trocar de sala recolhe de novo', (tester) async {
      await pump(tester, kTeamRoom);
      await show(tester, page([msg(0), ...events]));
      await tester.tap(find.byKey(summary));
      await tester.pump();

      await pump(tester, kDirectRoom);
      await show(tester, page([msg(0), ...events]));
      await pump(tester, kTeamRoom);
      await show(tester, page([msg(0), ...events]));

      expect(find.byKey(summary), findsOneWidget);
    });
  });
}
