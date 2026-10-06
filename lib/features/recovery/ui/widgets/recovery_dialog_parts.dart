import 'package:flutter/material.dart';

import '../../../../app/theme.dart';

class RecoveryDialogFrame extends StatelessWidget {
  const RecoveryDialogFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      backgroundColor: colors.conversationBackground,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.dialogBorder),
      ),
      child: SizedBox(
        width: 460,
        child: Padding(padding: const EdgeInsets.all(30), child: child),
      ),
    );
  }
}

class RecoveryDialogHeading extends StatelessWidget {
  const RecoveryDialogHeading({
    super.key,
    required this.title,
    required this.body,
    this.bodyColor,
    this.bodyKey,
  });

  final String title;

  final String body;

  final Color? bodyColor;

  final Key? bodyKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: AppFonts.serif,
            fontSize: 28,
            height: 1.15,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          key: bodyKey,
          style: TextStyle(
            fontSize: 14,
            height: 1.55,
            color: bodyColor ?? colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class RecoveryPrimaryButton extends StatelessWidget {
  const RecoveryPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;

  final VoidCallback? onPressed;

  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1,
      child: FilledButton(
        autofocus: autofocus,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.accent,
          disabledForegroundColor: colors.onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class RecoverySecondaryButton extends StatelessWidget {
  const RecoverySecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: context.colors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        textStyle: const TextStyle(fontSize: 14),
      ),
      child: Text(label),
    );
  }
}

class RecoveryProgressBar extends StatelessWidget {
  const RecoveryProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        minHeight: 6,
        backgroundColor: colors.surfaceHigh,
        color: colors.accent,
      ),
    );
  }
}
