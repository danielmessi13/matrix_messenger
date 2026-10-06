import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository.dart';
import 'package:matrix_messenger/features/rooms/ui/room_link/widgets/copy_room_link_button.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;
  late List<String> clipboard;

  setUp(() {
    repository = FakeRoomRepository();
    clipboard = [];
  });

  tearDown(() => repository.dispose());

  Future<void> pump(WidgetTester tester, String roomId) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      RepositoryProvider<RoomRepository>.value(
        value: repository,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(
              child: CopyRoomLinkButton(key: ValueKey(roomId), roomId: roomId),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('copia o link e mostra Link copiado por 2 s', (tester) async {
    await pump(tester, '!a:b.c');
    expect(find.byTooltip('Copiar link da sala'), findsOneWidget);

    await tester.tap(find.byKey(const Key('copy_room_link')));
    await tester.pump();

    expect(clipboard, ['https://matrix.to/#/!a:b.c?via=b.c']);
    expect(find.byTooltip('Link copiado'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    // O clique esconde a dica; ela precisa reaparecer com o resultado.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Link copiado'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('Copiar link da sala'), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.text('Link copiado'), findsNothing);
  });

  testWidgets('sem link mostra a falha', (tester) async {
    repository.roomLinkValue = null;
    await pump(tester, '!a:b.c');

    await tester.tap(find.byKey(const Key('copy_room_link')));
    await tester.pump();

    expect(find.byTooltip('Não foi possível copiar o link'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Não foi possível copiar o link'), findsOneWidget);
    expect(clipboard, isEmpty);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Icons.link), findsOneWidget);
    expect(find.text('Não foi possível copiar o link'), findsNothing);
  });

  testWidgets('trocar de sala recomeça em Copiar link da sala', (
    tester,
  ) async {
    await pump(tester, '!a:b.c');
    await tester.tap(find.byKey(const Key('copy_room_link')));
    await tester.pump();
    expect(find.byTooltip('Link copiado'), findsOneWidget);

    await pump(tester, '!b:b.c');
    await tester.pump();

    expect(find.byTooltip('Copiar link da sala'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
