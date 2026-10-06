import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/threads/domain/models/recent_thread.dart';
import 'package:matrix_messenger/features/threads/ui/view_models/recent_threads_state.dart';
import 'package:matrix_messenger/features/threads/ui/widgets/recent_threads_pane.dart';

import '../../../../../testing/desktop_size.dart';
import '../../../../../testing/models/recent_thread.dart';
import '../../../../../testing/models/room.dart';

void main() {
  late List<RecentThread> selected;
  late int retries;

  setUp(() {
    selected = [];
    retries = 0;
  });

  Future<void> pump(
    WidgetTester tester,
    RecentThreadsState state, {
    bool expanded = true,
    String? selectedRoomId,
    String? openThreadId,
  }) async {
    useDesktopSize(tester, const Size(1440, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Row(
            children: [
              RecentThreadsPane(
                expanded: expanded,
                state: state,
                rooms: [kTeamRoom, kDirectRoom],
                selectedRoomId: selectedRoomId,
                openThreadId: openThreadId,
                now: kNow,
                onSelect: selected.add,
                onRetry: () => retries++,
                onToggle: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lista as threads com sala, raiz e atividade', (tester) async {
    await pump(
      tester,
      RecentThreadsState(
        status: RecentThreadsStatus.ready,
        threads: [kTeamThread, kDirectThread],
      ),
    );

    expect(find.text('Threads recentes'), findsOneWidget);
    expect(find.text('# lançamento-q4'), findsOneWidget);
    expect(find.text('Carla: Quem revisa o deck?'), findsOneWidget);
    expect(find.text('3 respostas · última de Diego às 11:05'), findsOneWidget);
    expect(find.text('Eu pego a parte de números.'), findsOneWidget);
    expect(find.text('Ana Ribeiro'), findsOneWidget);
  });

  testWidgets('sem marcação de não lida', (tester) async {
    await pump(
      tester,
      RecentThreadsState(
        status: RecentThreadsStatus.ready,
        threads: [kTeamThread],
      ),
    );

    expect(find.textContaining('nova'), findsNothing);
  });

  testWidgets('clique entrega a thread', (tester) async {
    await pump(
      tester,
      RecentThreadsState(
        status: RecentThreadsStatus.ready,
        threads: [kTeamThread],
      ),
    );

    await tester.tap(
      find.byKey(
        Key('thread_${kTeamThread.roomId}_${kTeamThread.rootEventId}'),
      ),
    );

    expect(selected, [kTeamThread]);
  });

  testWidgets('thread de sala que não está na lista não aparece', (
    tester,
  ) async {
    final orphan = RecentThread(
      roomId: '!saiu:b.c',
      rootEventId: r'$x',
      root: kTeamThread.root,
      replyCount: 0,
      activity: kNow,
    );
    await pump(
      tester,
      RecentThreadsState(
        status: RecentThreadsStatus.ready,
        threads: [orphan],
      ),
    );

    expect(find.text('Nenhuma thread recente'), findsOneWidget);
  });

  testWidgets('carregando e vazia mostra o indicador', (tester) async {
    useDesktopSize(tester, const Size(1440, 900));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Row(
            children: [
              RecentThreadsPane(
                expanded: true,
                state: const RecentThreadsState(),
                rooms: const [],
                selectedRoomId: null,
                now: kNow,
                onSelect: (_) {},
                onRetry: () {},
                onToggle: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('recent_threads_loading')), findsOneWidget);
  });

  testWidgets('pronta e vazia mostra Nenhuma thread recente', (tester) async {
    await pump(
      tester,
      const RecentThreadsState(status: RecentThreadsStatus.ready),
    );

    expect(find.text('Nenhuma thread recente'), findsOneWidget);
  });

  testWidgets('falha e vazia oferece tentar de novo', (tester) async {
    await pump(
      tester,
      const RecentThreadsState(status: RecentThreadsStatus.failed),
    );

    expect(find.text('Não foi possível carregar as threads'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recent_threads_retry')));
    expect(retries, 1);
  });

  testWidgets('falha com threads mostra a lista', (tester) async {
    await pump(
      tester,
      RecentThreadsState(
        status: RecentThreadsStatus.failed,
        threads: [kTeamThread],
      ),
    );

    expect(find.text('Carla: Quem revisa o deck?'), findsOneWidget);
    expect(find.byKey(const Key('recent_threads_retry')), findsNothing);
  });

  testWidgets('recolhida mostra o avatar da sala de cada thread', (
    tester,
  ) async {
    await pump(
      tester,
      RecentThreadsState(
        status: RecentThreadsStatus.ready,
        threads: [kTeamThread, kDirectThread],
      ),
      expanded: false,
    );

    final team = find.byKey(
      Key('thread_avatar_${kTeamThread.roomId}_${kTeamThread.rootEventId}'),
    );
    expect(team, findsOneWidget);
    expect(
      find.byKey(
        Key(
          'thread_avatar_${kDirectThread.roomId}_${kDirectThread.rootEventId}',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(team);
    expect(selected, [kTeamThread]);
  });

  testWidgets('recolhida: tooltip com a sala e o início da raiz', (
    tester,
  ) async {
    await pump(
      tester,
      RecentThreadsState(
        status: RecentThreadsStatus.ready,
        threads: [kTeamThread],
      ),
      expanded: false,
    );

    expect(
      find.byTooltip('# lançamento-q4\nCarla: Quem revisa o deck?'),
      findsOneWidget,
    );
  });

  testWidgets('destaca só a thread aberta, não as outras da mesma sala', (
    tester,
  ) async {
    final other = RecentThread(
      roomId: kTeamThread.roomId,
      rootEventId: r'$outra-raiz',
      root: kTeamThread.root,
      replyCount: 0,
      activity: kNow,
    );
    await pump(
      tester,
      RecentThreadsState(
        status: RecentThreadsStatus.ready,
        threads: [kTeamThread, other],
      ),
      selectedRoomId: kTeamRoom.id,
      openThreadId: kTeamThread.rootEventId,
    );

    Color? tileColor(String root) => tester
        .widget<Material>(
          find
              .ancestor(
                of: find.byKey(Key('thread_${kTeamThread.roomId}_$root')),
                matching: find.byType(Material),
              )
              .first,
        )
        .color;

    expect(tileColor(kTeamThread.rootEventId), isNot(Colors.transparent));
    expect(tileColor(r'$outra-raiz'), Colors.transparent);
  });
}
