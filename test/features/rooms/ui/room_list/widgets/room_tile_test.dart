import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/widgets/room_avatar_tile.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/widgets/room_tile.dart';

import '../../../../../../testing/models/room.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SizedBox(width: 480, child: child)),
    ),
  );

  testWidgets('mostra nome, não lidas, horário e prévia', (tester) async {
    await pump(
      tester,
      RoomTile(
        room: kTeamRoom,
        selected: false,
        unread: kTeamRoom.unreadMessages,
        now: kNow,
        onTap: () {},
      ),
    );

    expect(find.text('# lançamento-q4'), findsOneWidget);
    expect(find.text('4 novas'), findsOneWidget);
    expect(find.text('10:42'), findsOneWidget);
    expect(find.text('Carla: Subi a versão final do deck.'), findsOneWidget);
  });

  Widget tile(Room room, {int unread = 0}) => SingleChildScrollView(
    child: RoomTile(
      room: room,
      selected: false,
      unread: unread,
      now: kNow,
      onTap: () {},
    ),
  );

  Room withLatest(LatestMessageKind kind) => Room(
    id: '!e:b.c',
    name: 'e',
    isDirect: true,
    latest: LatestMessage(
      senderName: 'Ana',
      isOwn: false,
      kind: kind,
      body: 'oi',
      timestamp: kNow,
    ),
  );

  testWidgets('sem mensagem o tile tem a mesma altura e o nome centralizado', (
    tester,
  ) async {
    await pump(tester, tile(const Room(id: '!v:b.c', name: 'v')));
    final emptyHeight = tester.getSize(find.byType(RoomTile)).height;
    final tileCenter = tester.getCenter(find.byType(RoomTile)).dy;
    final nameCenter = tester.getCenter(find.text('# v')).dy;
    expect(find.text('oi'), findsNothing);

    await pump(tester, tile(withLatest(LatestMessageKind.text)));
    expect(tester.getSize(find.byType(RoomTile)).height, emptyHeight);
    expect((nameCenter - tileCenter).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('com não lidas e sem prévia o tile mantém a mesma altura', (
    tester,
  ) async {
    await pump(tester, tile(const Room(id: '!v:b.c', name: 'v'), unread: 3));
    final emptyHeight = tester.getSize(find.byType(RoomTile)).height;
    expect(find.text('3 novas'), findsOneWidget);

    await pump(tester, tile(withLatest(LatestMessageKind.text), unread: 3));
    expect(tester.getSize(find.byType(RoomTile)).height, emptyHeight);
  });

  testWidgets('mensagem cifrada mostra só o texto, sem ícone', (tester) async {
    await pump(tester, tile(withLatest(LatestMessageKind.encrypted)));

    expect(find.text('Mensagem criptografada'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('convite troca o horário pela etiqueta', (tester) async {
    await pump(
      tester,
      RoomTile(
        room: kInviteRoom,
        selected: false,
        unread: kInviteRoom.unreadMessages,
        now: kNow,
        onTap: () {},
      ),
    );

    expect(find.text('Convite'), findsOneWidget);
    expect(find.text('Convite para entrar'), findsOneWidget);
  });

  testWidgets('sem não lidas não mostra "novas"', (tester) async {
    await pump(
      tester,
      RoomTile(
        room: kQuietRoom,
        selected: false,
        unread: kQuietRoom.unreadMessages,
        now: kNow,
        onTap: () {},
      ),
    );

    expect(find.textContaining('nova'), findsNothing);
    expect(find.text('Ontem'), findsOneWidget);
  });

  testWidgets('tocar chama onTap', (tester) async {
    var taps = 0;
    await pump(
      tester,
      RoomTile(
        room: kDirectRoom,
        selected: true,
        unread: 0,
        now: kNow,
        onTap: () => taps++,
      ),
    );

    await tester.tap(find.byKey(Key('room_${kDirectRoom.id}')));

    expect(taps, 1);
  });

  testWidgets('avatar recolhido mostra iniciais e não lidas', (tester) async {
    var taps = 0;
    await pump(
      tester,
      RoomAvatarTile(
        room: kDirectRoom,
        selected: false,
        unread: kDirectRoom.unreadMessages,
        onTap: () => taps++,
      ),
    );

    expect(find.text('AR'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(Key('room_avatar_${kDirectRoom.id}')));
    expect(taps, 1);
  });
}
