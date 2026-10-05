import 'package:flutter/material.dart';

abstract final class AppFonts {
  static const serif = 'Newsreader';
  static const sans = 'IBMPlexSans';
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.listBackground,
    required this.conversationBackground,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHigh,
    required this.border,
    required this.borderStrong,
    required this.rowDivider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.icon,
    required this.accent,
    required this.accentHover,
    required this.selectedRow,
    required this.hoverRow,
    required this.activeFilter,
  });

  static const dark = AppColors(
    background: Color(0xFF12110F),
    listBackground: Color(0xFF161512),
    conversationBackground: Color(0xFF1A1916),
    surface: Color(0xFF1F1D19),
    surfaceRaised: Color(0xFF22201C),
    surfaceHigh: Color(0xFF2A2823),
    border: Color(0xFF2B2924),
    borderStrong: Color(0xFF34312B),
    rowDivider: Color(0xFF22201C),
    textPrimary: Color(0xFFECE7DC),
    textSecondary: Color(0xFFA39C8F),
    textMuted: Color(0xFF857F73),
    icon: Color(0xFFB3AC9F),
    accent: Color(0xFFE4896A),
    accentHover: Color(0xFFF99C7C),
    selectedRow: Color(0xFF201E1A),
    hoverRow: Color(0xFF1C1A17),
    activeFilter: Color(0xFF24221D),
  );

  final Color background;
  final Color listBackground;
  final Color conversationBackground;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHigh;
  final Color border;
  final Color borderStrong;
  final Color rowDivider;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color icon;
  final Color accent;
  final Color accentHover;
  final Color selectedRow;
  final Color hoverRow;
  final Color activeFilter;

  // O app tem um tema só; não há transição entre temas para interpolar.
  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => this;
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}

ThemeData buildAppTheme() {
  const colors = AppColors.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: colors.accent,
        onPrimary: colors.background,
        surface: colors.background,
        onSurface: colors.textPrimary,
        onSurfaceVariant: colors.textSecondary,
        outline: colors.borderStrong,
        outlineVariant: colors.border,
      );
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: AppFonts.sans,
    scaffoldBackgroundColor: colors.background,
    dividerColor: colors.border,
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: colors.textPrimary, fontSize: 12.5),
    ),
    extensions: const [colors],
  );
}
