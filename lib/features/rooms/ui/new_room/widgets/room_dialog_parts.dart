import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';

class RoomDialogAlert extends StatelessWidget {
  const RoomDialogAlert({super.key, required this.title, required this.detail});

  final String title;

  final String detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.dangerSurface.withValues(alpha: 0.55),
        border: Border.all(color: colors.danger.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.danger),
            ),
            child: Text(
              '!',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.dangerText,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(fontSize: 13, color: colors.dangerText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RoomDialogActions extends StatelessWidget {
  const RoomDialogActions({
    super.key,
    required this.submitKey,
    required this.label,
    required this.busy,
    required this.canSubmit,
    required this.onSubmit,
  });

  final Key submitKey;

  final String label;

  final bool busy;

  final bool canSubmit;

  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            key: const Key('new_room_cancel'),
            onPressed: busy ? null : () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              visualDensity: VisualDensity.standard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Cancelar',
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Opacity(
            opacity: canSubmit || busy ? 1 : 0.45,
            child: FilledButton(
              key: submitKey,
              onPressed: canSubmit ? onSubmit : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                // No desktop a densidade adaptativa é compacta e encolhe o botão.
                visualDensity: VisualDensity.standard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                backgroundColor: colors.accent,
                foregroundColor: colors.onAccent,
                disabledBackgroundColor: colors.accent,
                disabledForegroundColor: colors.onAccent,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy) ...[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onAccent,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(label),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
