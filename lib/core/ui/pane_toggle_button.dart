import 'package:flutter/material.dart';

import '../../app/theme.dart';

class PaneToggleButton extends StatelessWidget {
  const PaneToggleButton({
    super.key,
    required this.pointsLeft,
    required this.tooltip,
    required this.onPressed,
    this.size = 32,
  });

  final bool pointsLeft;

  final String tooltip;

  final VoidCallback onPressed;

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          hoverColor: colors.borderStrong,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              pointsLeft ? Icons.chevron_left : Icons.chevron_right,
              size: 18,
              color: colors.icon,
            ),
          ),
        ),
      ),
    );
  }
}
