import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/conversation_pane.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';

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

  const typingLine = Key('typing_indicator');
  const field = Key('message_field');

  Future<void> pumpReady(WidgetTester tester) async {
    useDesktopSize(tester);
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
              room: kTeamRoom,
              now: kDay.add(const Duration(hours: 12)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    repository.conversation.snapshots.add(kSnapshot);
    await tester.pump();
    await tester.pump();
  }

  Future<void> typing(WidgetTester tester, List<String> names) async {
    repository.conversation.typingNames.add(names);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('mostra quem está digitando acima do campo sem mover o campo', (
    tester,
  ) async {
    await pumpReady(tester);
    expect(find.byKey(typingLine), findsNothing);
    final before = tester.getRect(find.byKey(field));

    await typing(tester, ['Bob', 'Ana']);

    expect(
      find.descendant(
        of: find.byKey(typingLine),
        matching: find.text('Bob e Ana estão digitando…'),
      ),
      findsOneWidget,
    );
    final line = tester.getRect(find.byKey(typingLine));
    final after = tester.getRect(find.byKey(field));
    expect(line.bottom, lessThanOrEqualTo(after.top));
    expect(after, before);

    await typing(tester, []);

    expect(find.byKey(typingLine), findsNothing);
    expect(tester.getRect(find.byKey(field)), before);
  });

  testWidgets('digitar avisa a conversa e enviar avisa que parou', (
    tester,
  ) async {
    await pumpReady(tester);

    await tester.enterText(find.byKey(field), 'o');
    await tester.enterText(find.byKey(field), 'olá');
    expect(repository.conversation.typingSent, [true]);

    await tester.tap(find.byKey(const Key('message_send')));
    await tester.pump();

    expect(repository.conversation.sent, ['olá']);
    expect(repository.conversation.typingSent, [true, false]);
  });

  testWidgets('apagar o rascunho avisa que parou', (tester) async {
    await pumpReady(tester);

    await tester.enterText(find.byKey(field), 'olá');
    await tester.enterText(find.byKey(field), '');

    expect(repository.conversation.typingSent, [true, false]);
  });
}
