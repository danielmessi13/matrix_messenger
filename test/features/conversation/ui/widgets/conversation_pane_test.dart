import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/conversation_pane.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../testing/models/message.dart';
import '../../../../../testing/models/room.dart';

void main() {
  late FakeConversationRepository repository;

  setUp(() => repository = FakeConversationRepository());

  Future<void> pump(
    WidgetTester tester,
    Room? room, {
    Size size = const Size(1440, 900),
  }) async {
    useDesktopSize(tester, size);
    await tester.pumpWidget(
      RepositoryProvider<ConversationRepository>.value(
        value: repository,
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

  testWidgets('enviar pelo campo chama a conversa', (tester) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);

    await tester.enterText(find.byKey(const Key('message_field')), 'olá');
    await tester.pump();
    await tester.tap(find.byKey(const Key('message_send')));
    await tester.pump();

    expect(repository.conversation.sent, ['olá']);
  });

  testWidgets('expandir thread pelo chip', (tester) async {
    await pump(tester, kTeamRoom);
    await show(tester, kSnapshot);

    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Recolher thread'), findsOneWidget);
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
}
