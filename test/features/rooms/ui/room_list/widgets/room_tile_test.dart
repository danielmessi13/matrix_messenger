import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
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
