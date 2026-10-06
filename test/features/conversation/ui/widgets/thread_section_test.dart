import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/thread_section.dart';

import '../../../../../testing/models/message.dart';

void main() {
  Future<int Function()> pump(
    WidgetTester tester, {
    ThreadSummary? summary,
    bool open = false,
  }) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ThreadSection(
            rootEventId: '\$root',
            summary: summary,
            open: open,
            onTap: () => taps++,
          ),
        ),
      ),
    );
    return () => taps;
  }

  testWidgets('recolhida mostra o total e a última resposta', (tester) async {
    final taps = await pump(tester, summary: kThreadRoot.thread);

    expect(find.text('4 respostas'), findsOneWidget);
    expect(find.text('última de Ana às 10:51'), findsOneWidget);
    expect(find.text('→'), findsOneWidget);
    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));

    expect(taps(), 1);
  });

  testWidgets('com respostas novas mostra o ponto e "N novas respostas"', (
    tester,
  ) async {
    await pump(
      tester,
      summary: ThreadSummary(
        rootEventId: '\$root',
        replies: 4,
        unread: 2,
        latestSender: 'Ana Ribeiro',
        latestAt: DateTime(2026, 10, 4, 10, 51),
      ),
    );

    expect(find.byKey(const Key('thread_new_dot')), findsOneWidget);
    expect(find.text('2 novas respostas'), findsOneWidget);
    expect(find.text('de 4 · última de Ana às 10:51'), findsOneWidget);
  });

  testWidgets('aberta mostra "Vendo no painel" e fechar', (tester) async {
    await pump(tester, summary: kThreadRoot.thread, open: true);

    expect(find.text('Vendo no painel'), findsOneWidget);
    expect(find.text('4 respostas · fechar'), findsOneWidget);
    expect(find.text('×'), findsOneWidget);
  });

  testWidgets('thread nova aberta, sem resumo, só oferece fechar', (
    tester,
  ) async {
    await pump(tester, open: true);

    expect(find.text('Vendo no painel'), findsOneWidget);
    expect(find.text('fechar'), findsOneWidget);
  });
}
