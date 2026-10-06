import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/ui/animated_pane.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool expanded}) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              AnimatedPane(
                key: const Key('pane'),
                expanded: expanded,
                expandedWidth: 400,
                compactWidth: 80,
                decoration: const BoxDecoration(),
                expandedChild: const SizedBox(key: Key('wide')),
                compactChild: const SizedBox(key: Key('compact')),
              ),
            ],
          ),
        ),
      );

  double width(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('pane'))).width;

  testWidgets('recolher anima a largura e troca o conteúdo no fim', (
    tester,
  ) async {
    await pump(tester, expanded: true);
    expect(width(tester), 400);

    await pump(tester, expanded: false);
    await tester.pump(kPaneAnimationDuration ~/ 2);
    expect(width(tester), inExclusiveRange(80, 400));
    expect(find.byKey(const Key('wide')), findsOneWidget);
    expect(find.byKey(const Key('compact')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(width(tester), 80);
    expect(find.byKey(const Key('wide')), findsNothing);
    expect(find.byKey(const Key('compact')), findsOneWidget);
  });

  testWidgets('conteúdo fica na largura final durante a animação', (
    tester,
  ) async {
    await pump(tester, expanded: false);
    await pump(tester, expanded: true);
    await tester.pump(kPaneAnimationDuration ~/ 2);

    expect(tester.getSize(find.byKey(const Key('wide'))).width, 400);
    expect(tester.takeException(), isNull);
  });
}
