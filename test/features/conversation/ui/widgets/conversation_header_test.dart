import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/conversation_header.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;

  setUp(() => repository = FakeRoomRepository());

  tearDown(() => repository.dispose());

  Future<void> pump(WidgetTester tester, Room room) async {
    useDesktopSize(tester);
    await tester.pumpWidget(
      RepositoryProvider<RoomRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: ConversationHeader(room: room)),
        ),
      ),
    );
  }

  testWidgets('sala pública mostra o botão de copiar link', (tester) async {
    await pump(
      tester,
      const Room(id: '!pub:b.c', name: 'aberta', isPublic: true),
    );

    expect(find.byKey(const Key('copy_room_link')), findsOneWidget);
  });

  testWidgets('sala privada e DM não mostram o botão', (tester) async {
    await pump(tester, const Room(id: '!priv:b.c', name: 'fechada'));
    expect(find.byKey(const Key('copy_room_link')), findsNothing);

    await pump(
      tester,
      const Room(id: '!dm:b.c', name: 'Ana', isDirect: true, heroes: ['Ana']),
    );
    expect(find.byKey(const Key('copy_room_link')), findsNothing);
  });

  testWidgets('DM pública também não mostra o botão', (tester) async {
    await pump(
      tester,
      const Room(
        id: '!dm:b.c',
        name: 'Ana',
        isPublic: true,
        isDirect: true,
        heroes: ['Ana'],
      ),
    );

    expect(find.byKey(const Key('copy_room_link')), findsNothing);
  });
}
