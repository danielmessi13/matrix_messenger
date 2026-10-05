import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';

void main() {
  test('tema escuro com os tokens do mockup', () {
    final theme = buildAppTheme();

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF12110F));
    expect(theme.colorScheme.primary, const Color(0xFFE4896A));
    expect(theme.extension<AppColors>(), AppColors.dark);
    expect(theme.textTheme.bodyMedium?.fontFamily, AppFonts.sans);
  });

  testWidgets('context.colors lê a extensão do tema', (tester) async {
    late AppColors colors;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) {
            colors = context.colors;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(colors.accent, const Color(0xFFE4896A));
  });
}
