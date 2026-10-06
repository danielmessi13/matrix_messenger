import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/rooms/domain/models/message_hit.dart';
import 'package:matrix_messenger/features/rooms/domain/models/message_search_failure.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_filter.dart';
import 'package:matrix_messenger/features/rooms/domain/models/sync_state.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/view_models/message_search_state.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/view_models/room_list_state.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/widgets/room_list_pane.dart';

import '../../../../../../testing/models/room.dart';

void main() {
  late List<MessageHit> opened;
  late int loadMore;
  late int retries;

  setUp(() {
    opened = [];
    loadMore = 0;
    retries = 0;
  });

  Future<List<String>> pump(
    WidgetTester tester,
    RoomListState state, {
    bool expanded = true,
  }) async {
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Row(
            children: [
              RoomListPane(
                expanded: expanded,
                state: state,
                now: kNow,
                onSelect: selected.add,
                onToggle: () {},
                onOpenMessage: opened.add,
                onLoadMoreMessages: () => loadMore++,
                onRetryMessages: () => retries++,
              ),
            ],
          ),
        ),
      ),
    );
    return selected;
  }

  testWidgets('antes da primeira lista mostra esqueleto', (tester) async {
    await pump(tester, const RoomListState());

    expect(find.byKey(const Key('room_skeleton')), findsNWidgets(6));
  });

  testWidgets('cabeçalho com filtro e não lidas', (tester) async {
    await pump(tester, RoomListState(rooms: kRooms, loaded: true));

    expect(find.text('Caixa de entrada'), findsOneWidget);
    expect(find.text('6 não lidas'), findsOneWidget);
    expect(find.text('# lançamento-q4'), findsOneWidget);
  });

  testWidgets('uma não lida fica no singular', (tester) async {
    const room = Room(id: '!um:matrix.org', name: 'um', unreadMessages: 1);
    await pump(tester, const RoomListState(rooms: [room], loaded: true));

    expect(find.text('1 não lida'), findsOneWidget);
  });

  testWidgets('sem não lidas mostra "Tudo em dia"', (tester) async {
    await pump(tester, RoomListState(rooms: [kQuietRoom], loaded: true));

    expect(find.text('Tudo em dia'), findsOneWidget);
  });

  testWidgets('lista vazia mostra a mensagem do mockup', (tester) async {
    await pump(
      tester,
      RoomListState(
        rooms: [kTeamRoom],
        loaded: true,
        filter: RoomFilter.direct,
      ),
    );

    expect(find.text('Nenhuma conversa encontrada.'), findsOneWidget);
  });

  testWidgets('offline e erro mostram a faixa', (tester) async {
    await pump(
      tester,
      RoomListState(rooms: kRooms, loaded: true, syncState: SyncState.offline),
    );
    expect(find.text('Sem conexão — mostrando dados salvos'), findsOneWidget);

    await pump(
      tester,
      RoomListState(rooms: kRooms, loaded: true, syncState: SyncState.error),
    );
    expect(
      find.text('Problema ao sincronizar. Tentando novamente…'),
      findsOneWidget,
    );
  });

  testWidgets('servidor sem suporte troca a lista pela mensagem', (
    tester,
  ) async {
    await pump(tester, const RoomListState(syncState: SyncState.unsupported));

    expect(
      find.text('Este servidor não suporta a sincronização usada pelo app.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('room_skeleton')), findsNothing);
  });

  testWidgets('tocar numa sala chama onSelect com o id', (tester) async {
    final selected = await pump(
      tester,
      RoomListState(rooms: kRooms, loaded: true),
    );

    await tester.tap(find.byKey(Key('room_${kDirectRoom.id}')));

    expect(selected, [kDirectRoom.id]);
  });

  testWidgets('recolhida mostra só os avatares', (tester) async {
    await pump(
      tester,
      RoomListState(rooms: kRooms, loaded: true),
      expanded: false,
    );

    expect(find.byKey(Key('room_avatar_${kTeamRoom.id}')), findsOneWidget);
    expect(find.text('Caixa de entrada'), findsNothing);
  });

  double paneWidth(WidgetTester tester) =>
      tester.getSize(find.byType(RoomListPane)).width;

  const lonely = Room(id: '!so:matrix.org', name: 'só', unreadMessages: 1);

  testWidgets('recolhida e sem salas no filtro, a barra some', (tester) async {
    await pump(
      tester,
      const RoomListState(rooms: [lonely], loaded: true),
      expanded: false,
    );
    expect(paneWidth(tester), kRoomListCompactWidth);

    await pump(
      tester,
      const RoomListState(
        rooms: [lonely],
        loaded: true,
        filter: RoomFilter.direct,
      ),
      expanded: false,
    );
    await tester.pumpAndSettle();
    expect(paneWidth(tester), 0);

    await pump(
      tester,
      const RoomListState(rooms: [lonely], loaded: true),
      expanded: false,
    );
    await tester.pumpAndSettle();
    expect(paneWidth(tester), kRoomListCompactWidth);
  });

  testWidgets('expandida e sem salas no filtro, a barra fica', (tester) async {
    await pump(
      tester,
      const RoomListState(
        rooms: [lonely],
        loaded: true,
        filter: RoomFilter.direct,
      ),
    );

    expect(paneWidth(tester), kRoomListWidth);
    expect(find.text('Nenhuma conversa encontrada.'), findsOneWidget);
  });

  group('busca de mensagens', () {
    final hit = MessageHit(
      roomId: kTeamRoom.id,
      roomName: 'lançamento-q4',
      eventId: r'$deploy',
      senderName: 'Diego Alves',
      body: 'O deploy de amanhã ficou para as 15h.',
      timestamp: DateTime(2026, 10, 4, 10, 5),
    );

    RoomListState searching(MessageSearch messages) => RoomListState(
      rooms: kRooms,
      loaded: true,
      query: 'deploy',
      messages: messages,
    );

    testWidgets('resultado mostra sala, remetente, trecho e hora', (
      tester,
    ) async {
      await pump(
        tester,
        searching(
          MessageSearch(status: MessageSearchStatus.ready, hits: [hit]),
        ),
      );

      expect(find.text('# lançamento-q4'), findsOneWidget);
      expect(find.text('10:05'), findsOneWidget);
      expect(
        find.text('Diego Alves: O deploy de amanhã ficou para as 15h.'),
        findsOneWidget,
      );
      expect(find.text('1 mensagem'), findsOneWidget);
      expect(find.byKey(const Key('encrypted_rooms_hint')), findsOneWidget);
      expect(find.byKey(Key('room_${kDirectRoom.id}')), findsNothing);

      final rich = tester.widget<RichText>(
        find.descendant(
          of: find.byKey(const Key(r'message_hit_$deploy')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is RichText &&
                widget.text.toPlainText().startsWith('Diego'),
          ),
        ),
      );
      final highlighted = <String>[];
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.style?.fontWeight == FontWeight.w600) {
          highlighted.add(span.text ?? '');
        }
        return true;
      });
      expect(highlighted, ['deploy']);

      await tester.tap(find.byKey(const Key(r'message_hit_$deploy')));
      expect(opened, [hit]);
    });

    testWidgets('com mais páginas, o botão pede a próxima', (tester) async {
      await pump(
        tester,
        searching(
          MessageSearch(
            status: MessageSearchStatus.ready,
            hits: [hit],
            nextBatch: 'b2',
          ),
        ),
      );

      expect(find.text('1+ mensagens'), findsOneWidget);
      await tester.tap(find.byKey(const Key('message_search_more')));
      expect(loadMore, 1);
    });

    testWidgets('carregando mostra o indicador depois de um instante', (
      tester,
    ) async {
      await pump(
        tester,
        searching(const MessageSearch(status: MessageSearchStatus.loading)),
      );
      expect(find.byKey(const Key('message_search_loading')), findsNothing);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('message_search_loading')), findsOneWidget);
    });

    testWidgets('vazio avisa e mantém a dica das salas cifradas', (
      tester,
    ) async {
      await pump(
        tester,
        searching(const MessageSearch(status: MessageSearchStatus.ready)),
      );

      expect(find.text('Nenhuma mensagem encontrada.'), findsOneWidget);
      expect(find.byKey(const Key('encrypted_rooms_hint')), findsOneWidget);
    });

    testWidgets('erro mostra a causa e tenta de novo', (tester) async {
      await pump(
        tester,
        searching(
          const MessageSearch(
            status: MessageSearchStatus.failed,
            failure: MessageSearchFailureType.network,
          ),
        ),
      );

      expect(find.text('Sem conexão com o servidor.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('message_search_retry')));
      expect(retries, 1);
    });
  });
}
