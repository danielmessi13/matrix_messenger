import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/reaction_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../testing/desktop_size.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<List<String>> pump(
    WidgetTester tester, {
    List<bool>? openChanges,
    double top = 40,
  }) async {
    useDesktopSize(tester);
    final selected = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.only(top: top, left: 40),
            child: Align(
              alignment: Alignment.topLeft,
              child: ReactionPickerButton(
                alignEnd: false,
                onSelected: selected.add,
                onOpenChanged: openChanges?.add,
                builder: (context, open) => TextButton(
                  key: const Key('open_picker'),
                  onPressed: open,
                  child: const Text('+'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return selected;
  }

  testWidgets('abre o seletor flutuante e avisa', (tester) async {
    final changes = <bool>[];
    await pump(tester, openChanges: changes);

    await tester.tap(find.byKey(const Key('open_picker')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reaction_picker')), findsOneWidget);
    expect(find.byType(EmojiPicker), findsOneWidget);
    expect(changes, [true]);
  });

  testWidgets('escolher um emoji repassa e fecha', (tester) async {
    final changes = <bool>[];
    final selected = await pump(tester, openChanges: changes);
    await tester.tap(find.byKey(const Key('open_picker')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('😀').first);
    await tester.pumpAndSettle();

    expect(selected, ['😀']);
    expect(find.byKey(const Key('reaction_picker')), findsNothing);
    expect(changes, [true, false]);
  });

  testWidgets('Esc fecha sem escolher', (tester) async {
    final selected = await pump(tester);
    await tester.tap(find.byKey(const Key('open_picker')));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reaction_picker')), findsNothing);
    expect(selected, isEmpty);
  });

  testWidgets('clique fora fecha', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('open_picker')));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(900, 700));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reaction_picker')), findsNothing);
  });

  testWidgets('perto do fim da tela abre para cima', (tester) async {
    useDesktopSize(tester);
    final height =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    await pump(tester, top: height - 80);
    await tester.tap(find.byKey(const Key('open_picker')));
    await tester.pumpAndSettle();

    final card = tester.getRect(find.byKey(const Key('reaction_picker')));
    final trigger = tester.getRect(find.byKey(const Key('open_picker')));
    expect(card.bottom, lessThanOrEqualTo(trigger.top));
  });

  testWidgets('rebuild do pai mantém o seletor aberto', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('open_picker')));
    await tester.pumpAndSettle();

    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('reaction_picker')), findsOneWidget);
  });

  testWidgets('descartado com o seletor aberto avisa que fechou', (
    tester,
  ) async {
    final changes = <bool>[];
    await pump(tester, openChanges: changes);
    await tester.tap(find.byKey(const Key('open_picker')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());

    expect(changes, [true, false]);
  });
}
