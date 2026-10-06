import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';

class NewRoomButton extends StatelessWidget {
  const NewRoomButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shortcut = defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘ N'
        : 'Ctrl N';
    return Tooltip(
      message: 'Nova sala ($shortcut)',
      // Brilho de 1px no topo, como o inset do design.
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.accentHighlight,
              colors.accentHighlight,
              colors.accentHighlight.withValues(alpha: 0),
              colors.accentHighlight.withValues(alpha: 0),
            ],
            stops: const [0, 1 / 40, 1 / 40, 1],
          ),
        ),
        child: FilledButton(
          key: const Key('new_room_button'),
          onPressed: onPressed,
          style: ButtonStyle(
            // Sem isso o Material aumenta a área de toque para 48px no Android (e nos testes).
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
            fixedSize: const WidgetStatePropertyAll(Size.fromHeight(40)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.fromLTRB(14, 0, 18, 0),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
            ),
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.pressed)
                  ? colors.accentPressed
                  : states.contains(WidgetState.hovered)
                  ? colors.accentHover
                  : colors.accent,
            ),
            foregroundColor: WidgetStatePropertyAll(colors.onAccent),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size.square(16),
                painter: _HashPainter(colors.onAccent),
              ),
              const SizedBox(width: 8),
              const Text('Nova sala'),
            ],
          ),
        ),
      ),
    );
  }
}

// Traços do SVG do design (viewBox 24): M9 4 7 20 · M17 4 15 20 · M4 9h16 · M3 15h16.
class _HashPainter extends CustomPainter {
  const _HashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.3 * scale
      ..strokeCap = StrokeCap.round;
    void line(double x1, double y1, double x2, double y2) => canvas.drawLine(
      Offset(x1 * scale, y1 * scale),
      Offset(x2 * scale, y2 * scale),
      paint,
    );
    line(9, 4, 7, 20);
    line(17, 4, 15, 20);
    line(4, 9, 20, 9);
    line(3, 15, 19, 15);
  }

  @override
  bool shouldRepaint(_HashPainter oldDelegate) => oldDelegate.color != color;
}
