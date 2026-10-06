import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/models/timeline_item.dart';
import 'message_labels.dart';

class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.messageId,
    required this.reactions,
    required this.alignEnd,
    this.onReact,
    this.trailing,
  });

  final String messageId;

  final List<MessageReaction> reactions;

  final bool alignEnd;

  // Nulo deixa os chips só leitura.
  final ValueChanged<String>? onReact;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Wrap(
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final reaction in reactions)
          _Chip(
            key: Key('reaction_${messageId}_${reaction.key}'),
            reaction: reaction,
            onTap: switch (onReact) {
              final onReact? => () => onReact(reaction.key),
              null => null,
            },
          ),
        ?trailing,
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.reaction, required this.onTap});

  final MessageReaction reaction;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mine = reaction.reactedByMe;
    return Tooltip(
      message: reactionTooltip(reaction),
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: mine
                  ? colors.accent.withValues(alpha: 0.16)
                  : colors.surfaceHigh,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: mine ? colors.accent : colors.borderStrong,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reaction.key, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 5),
                Text(
                  '${reaction.count}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: mine ? colors.accent : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
