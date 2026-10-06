import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../domain/models/timeline_item.dart';
import '../thread/view_models/thread_state.dart';
import '../thread/view_models/thread_view_model.dart';
import 'markdown_text.dart';
import 'message_labels.dart';

class ThreadSection extends StatelessWidget {
  const ThreadSection({
    super.key,
    required this.summary,
    required this.onToggle,
    this.viewModel,
  });

  final ThreadSummary summary;

  final VoidCallback onToggle;

  final ThreadViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final viewModel = this.viewModel;
    if (viewModel == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: OutlinedButton(
          key: Key('thread_toggle_${summary.rootEventId}'),
          onPressed: onToggle,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colors.borderStrong),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('▼', style: TextStyle(fontSize: 9, color: colors.accent)),
              const SizedBox(width: 10),
              Text(
                repliesLabel(summary.replies),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                  fontSize: 13.5,
                ),
              ),
              if (summary.unread > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    unreadRepliesLabel(summary.unread),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colors.background,
                    ),
                  ),
                ),
              ],
              if (threadSummaryLabel(summary) case final label
                  when label.isNotEmpty) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Text(
                'Expandir',
                style: TextStyle(color: colors.textPrimary, fontSize: 13.5),
              ),
            ],
          ),
        ),
      );
    }
    return BlocProvider.value(
      value: viewModel,
      child: _Replies(
        colors: colors,
        onCollapse: onToggle,
        rootEventId: summary.rootEventId,
      ),
    );
  }
}

class _Replies extends StatelessWidget {
  const _Replies({
    required this.colors,
    required this.onCollapse,
    required this.rootEventId,
  });

  final AppColors colors;

  final VoidCallback onCollapse;

  final String rootEventId;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 4, left: 20),
    padding: const EdgeInsets.only(left: 20),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: colors.borderStrong, width: 2)),
    ),
    child: BlocBuilder<ThreadViewModel, ThreadState>(
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...switch (state.status) {
            ThreadStatus.loading => [
              Text(
                'Carregando respostas…',
                style: TextStyle(color: colors.textMuted, fontSize: 13.5),
              ),
            ],
            ThreadStatus.failed => [
              Row(
                children: [
                  Text(
                    'Não foi possível carregar as respostas',
                    style: TextStyle(color: colors.textMuted, fontSize: 13.5),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: context.read<ThreadViewModel>().open,
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ],
            ThreadStatus.ready => [
              if (!state.reachedStart)
                state.loadingOlder
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Carregando respostas anteriores…',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 13.5,
                          ),
                        ),
                      )
                    : TextButton(
                        key: Key('thread_load_older_$rootEventId'),
                        onPressed: context.read<ThreadViewModel>().loadOlder,
                        child: const Text('Carregar respostas anteriores'),
                      ),
              for (final reply in state.replies) ...[
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: reply.senderName,
                        style: TextStyle(fontWeight: FontWeight.w600, color: colors.textPrimary),
                      ),
                      TextSpan(
                        text: '  ${formatMessageTime(reply.timestamp)}',
                        style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 14.5),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  markdownSpan(
                    reply.body ?? kindPlaceholder(reply.kind) ?? '',
                    style: TextStyle(fontSize: 14.5, height: 1.5, color: colors.textSecondary),
                    codeStyle: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          },
          TextButton.icon(
            key: Key('thread_toggle_$rootEventId'),
            onPressed: onCollapse,
            icon: Text('▲', style: TextStyle(fontSize: 9, color: colors.accent)),
            label: Text('Recolher thread', style: TextStyle(color: colors.accent, fontSize: 13.5)),
          ),
        ],
      ),
    ),
  );
}
