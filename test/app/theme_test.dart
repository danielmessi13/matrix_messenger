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

  test('tokens do botão e do diálogo de nova sala', () {
    const colors = AppColors.dark;

    expect(colors.accentHover, const Color(0xFFF59979));
    expect(colors.accentPressed, const Color(0xFFD37A5B));
    expect(colors.accentHighlight, const Color(0xFFFCAE93));
    expect(colors.onAccent, const Color(0xFF16110B));
    expect(colors.dialogBorder, const Color(0xFF3A3730));
    expect(colors.chip, const Color(0xFF2E2B25));
    expect(colors.danger, const Color(0xFFCA5551));
    expect(colors.dangerSurface, const Color(0xFF4F1A18));
    expect(colors.dangerText, const Color(0xFFF3C9BD));
    expect(colors.warning, const Color(0xFFD49648));
    expect(colors.warningText, const Color(0xFFE8AA4E));
  });
}
