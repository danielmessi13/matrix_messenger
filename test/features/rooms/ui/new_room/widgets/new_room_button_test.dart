import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/features/rooms/ui/new_room/widgets/new_room_button.dart';

void main() {
  Future<void> pump(WidgetTester tester, VoidCallback onPressed) =>
      tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Center(child: NewRoomButton(onPressed: onPressed)),
          ),
        ),
      );

  testWidgets('mostra o texto e chama onPressed', (tester) async {
    var pressed = 0;
    await pump(tester, () => pressed++);

    expect(find.text('Nova sala'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new_room_button')));
    expect(pressed, 1);
  });

  testWidgets('altura 40 e cor de destaque', (tester) async {
    await pump(tester, () {});

    final size = tester.getSize(find.byKey(const Key('new_room_button')));
    expect(size.height, 40);
    final style = tester
        .widget<FilledButton>(find.byKey(const Key('new_room_button')))
        .style!;
    expect(
      style.backgroundColor!.resolve(<WidgetState>{}),
      AppColors.dark.accent,
    );
    expect(
      style.backgroundColor!.resolve({WidgetState.hovered}),
      AppColors.dark.accentHover,
    );
    expect(
      style.backgroundColor!.resolve({WidgetState.pressed}),
      AppColors.dark.accentPressed,
    );
    expect(
      style.foregroundColor!.resolve(<WidgetState>{}),
      AppColors.dark.onAccent,
    );
  });

  testWidgets('tooltip mostra o atalho da plataforma', (tester) async {
    await pump(tester, () {});

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(
      tooltip.message,
      defaultTargetPlatform == TargetPlatform.macOS
          ? 'Nova sala (⌘ N)'
          : 'Nova sala (Ctrl N)',
    );
  }, variant: TargetPlatformVariant.desktop());
}
