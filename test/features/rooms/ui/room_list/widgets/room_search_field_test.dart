import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/widgets/room_search_field.dart';

void main() {
  testWidgets('digitar avisa a busca e o × limpa', (tester) async {
    final queries = <String>[];
    var cleared = 0;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: RoomSearchField(
            focusNode: focusNode,
            onChanged: queries.add,
            onCleared: () => cleared++,
          ),
        ),
      ),
    );

    expect(find.text('Buscar mensagens'), findsOneWidget);
    expect(find.byKey(const Key('room_search_clear')), findsNothing);
    await tester.enterText(find.byKey(const Key('room_search')), 'ana');
    await tester.pump();
    expect(queries.last, 'ana');

    await tester.tap(find.byKey(const Key('room_search_clear')));
    await tester.pump();
    expect(cleared, 1);
    expect(find.text('ana'), findsNothing);
  });
}
