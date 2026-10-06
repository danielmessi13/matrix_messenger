import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_filter.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/widgets/filter_rail.dart';

void main() {
  Future<List<RoomFilter>> pump(
    WidgetTester tester, {
    required bool expanded,
    VoidCallback? onToggle,
  }) async {
    final selected = <RoomFilter>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Row(
            children: [
              FilterRail(
                expanded: expanded,
                selected: RoomFilter.inbox,
                unreadByFilter: const {
                  RoomFilter.inbox: 14,
                  RoomFilter.mentions: 5,
                  RoomFilter.threads: 0,
                  RoomFilter.rooms: 11,
                  RoomFilter.direct: 3,
                },
                onSelect: selected.add,
                onToggle: onToggle ?? () {},
              ),
            ],
          ),
        ),
      ),
    );
    return selected;
  }

  testWidgets('recolhido mostra nomes curtos e badges', (tester) async {
    await pump(tester, expanded: false);

    expect(find.text('Entrada'), findsOneWidget);
    expect(find.text('Diretas'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('Caixa de entrada'), findsNothing);
  });

  testWidgets('expandido mostra o título e nomes completos', (tester) async {
    await pump(tester, expanded: true);

    expect(find.text('FILTROS'), findsOneWidget);
    expect(find.text('Caixa de entrada'), findsOneWidget);
  });

  testWidgets('tocar seleciona, inclusive Threads', (tester) async {
    final selected = await pump(tester, expanded: true);

    await tester.tap(find.byKey(const Key('filter_direct')));
    await tester.tap(find.byKey(const Key('filter_threads')));

    expect(selected, [RoomFilter.direct, RoomFilter.threads]);
    expect(find.byTooltip('Em breve'), findsNothing);
  });

  testWidgets('botão de recolher chama onToggle', (tester) async {
    var toggles = 0;
    await pump(tester, expanded: false, onToggle: () => toggles++);

    await tester.tap(find.byKey(const Key('toggle_filters')));

    expect(toggles, 1);
  });

  testWidgets('Threads não mostra número mesmo com valor no mapa', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: FilterRail(
            expanded: true,
            selected: RoomFilter.inbox,
            unreadByFilter: const {RoomFilter.threads: 7},
            onSelect: (_) {},
            onToggle: () {},
          ),
        ),
      ),
    );

    expect(find.text('7'), findsNothing);
  });
}
