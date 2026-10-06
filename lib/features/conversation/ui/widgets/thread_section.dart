import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/models/timeline_item.dart';
import 'message_labels.dart';

class ThreadSection extends StatelessWidget {
  const ThreadSection({
    super.key,
    required this.rootEventId,
    required this.open,
    required this.onTap,
    this.summary,
  });

  final String rootEventId;

  // Nulo numa thread recém-iniciada, ainda sem respostas.
  final ThreadSummary? summary;

  final bool open;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final summary = this.summary;
    final unread = open ? 0 : summary?.unread ?? 0;
    final last = summary == null ? '' : threadSummaryLabel(summary);
    final (label, detail) = switch ((open, summary)) {
      (true, null) => ('Vendo no painel', 'fechar'),
      (true, final summary?) => (
        'Vendo no painel',
        '${repliesLabel(summary.replies)} · fechar',
      ),
      (false, final summary?) when unread > 0 => (
        newRepliesLabel(unread),
        last.isEmpty
            ? 'de ${summary.replies}'
            : 'de ${summary.replies} · $last',
      ),
      (false, final summary?) => (repliesLabel(summary.replies), last),
      (false, null) => ('', ''),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: InkWell(
        key: Key('thread_toggle_$rootEventId'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        hoverColor: colors.surfaceRaised,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unread > 0) ...[
                Container(
                  key: const Key('thread_new_dot'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: colors.textMuted),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Text(
                open ? '×' : '→',
                style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
