import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_filter.dart';
import 'package:matrix_messenger/features/rooms/domain/models/sync_state.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/view_models/room_list_state.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/widgets/room_list_pane.dart';

import '../../../../../../testing/models/room.dart';

void main() {
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

  testWidgets('filtro Threads conta respostas de thread também na linha', (
    tester,
  ) async {
    const room = Room(
      id: '!thread:matrix.org',
      name: 'thread',
      unreadThreadReplies: 3,
    );
    await pump(
      tester,
      const RoomListState(
        rooms: [room],
        loaded: true,
        filter: RoomFilter.threads,
      ),
    );

    expect(find.text('3 não lidas'), findsOneWidget);
    expect(find.text('3 novas'), findsOneWidget);
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

  testWidgets('busca mostra "Resultados" e a contagem', (tester) async {
    await pump(
      tester,
      RoomListState(rooms: kRooms, loaded: true, query: 'ana'),
    );

    expect(find.text('Resultados'), findsOneWidget);
    expect(find.text('1 conversas'), findsNothing);
    expect(find.text('1 conversa'), findsOneWidget);
  });

  testWidgets('lista vazia mostra a mensagem do mockup', (tester) async {
    await pump(
      tester,
      RoomListState(
        rooms: kRooms,
        loaded: true,
        filter: RoomFilter.mentions,
        query: 'xyz',
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

  testWidgets('recolhida com busca sem resultado, a barra some', (
    tester,
  ) async {
    await pump(
      tester,
      const RoomListState(rooms: [lonely], loaded: true, query: 'xyz'),
      expanded: false,
    );
    await tester.pumpAndSettle();

    expect(paneWidth(tester), 0);
  });
}
