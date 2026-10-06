import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../../rooms/domain/models/room.dart';
import '../../../rooms/ui/room_list/widgets/room_labels.dart';
import '../../domain/models/timeline_item.dart';
import '../thread/view_models/thread_state.dart';
import '../thread/view_models/thread_view_model.dart';
import 'focus_flash.dart';
import 'markdown_text.dart';
import 'message_input.dart';
import 'message_labels.dart';
import 'message_tile.dart';

const threadPanelWidth = 400.0;

class ThreadPanel extends StatelessWidget {
  const ThreadPanel({
    super.key,
    required this.room,
    required this.rootEventId,
    required this.root,
    required this.viewModel,
    required this.onClose,
    required this.onGoToRoot,
  });

  final Room room;

  final String rootEventId;

  // Nulo se a raiz saiu da timeline carregada.
  final MessageItem? root;

  final ThreadViewModel viewModel;

  final VoidCallback onClose;

  final VoidCallback onGoToRoot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final root = this.root;
    return BlocProvider.value(
      value: viewModel,
      child: Container(
        key: const Key('thread_panel'),
        width: threadPanelWidth,
        decoration: BoxDecoration(
          color: colors.listBackground,
          border: Border(left: BorderSide(color: colors.border)),
        ),
        child: Column(
          children: [
            _Header(
              room: room,
              title: root == null ? 'Thread' : threadTitle(root),
              onClose: onClose,
            ),
            Expanded(
              child: _Replies(
                root: root,
                rootEventId: rootEventId,
                onGoToRoot: onGoToRoot,
              ),
            ),
            BlocBuilder<ThreadViewModel, ThreadState>(
              buildWhen: (a, b) =>
                  a.status != b.status || a.replyTo != b.replyTo,
              builder: (context, state) => MessageInput(
                placeholder: composerHint(
                  roomTitle: roomTitle(room),
                  replyTo: state.replyTo,
                  inThread: true,
                ),
                compact: true,
                autofocus: true,
                replyTo: state.replyTo,
                onCancelReply: viewModel.cancelReply,
                enabled: state.status == ThreadStatus.ready,
                onSend: viewModel.send,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.room,
    required this.title,
    required this.onClose,
  });

  final Room room;

  final String title;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 32, 16, 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roomTitle(room).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 1,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.serif,
                    fontSize: 30,
                    height: 1.1,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('thread_panel_close'),
            tooltip: 'Fechar thread (Esc)',
            onPressed: onClose,
            icon: Icon(Icons.close, size: 18, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Replies extends StatefulWidget {
  const _Replies({
    required this.root,
    required this.rootEventId,
    required this.onGoToRoot,
  });

  final MessageItem? root;

  final String rootEventId;

  final VoidCallback onGoToRoot;

  @override
  State<_Replies> createState() => _RepliesState();
}

class _RepliesState extends State<_Replies> with FocusFlash<_Replies> {
  void _onQuoteTap(String eventId) => eventId == widget.rootEventId
      ? widget.onGoToRoot()
      : context.read<ThreadViewModel>().goTo(eventId);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final viewModel = context.read<ThreadViewModel>();
    final muted = TextStyle(color: colors.textMuted, fontSize: 13.5);
    return BlocListener<ThreadViewModel, ThreadState>(
      listenWhen: (a, b) => a.replies != b.replies,
      listener: (context, state) =>
          pruneKeys(state.replies.map((reply) => reply.id)),
      child: BlocConsumer<ThreadViewModel, ThreadState>(
        listenWhen: (a, b) => a.focusRequest != b.focusRequest,
        listener: (context, state) {
          if (state.focusRequest case final request?) focusOn(request);
        },
        builder: (context, state) => SingleChildScrollView(
          // Invertida como a conversa: resposta nova aparece embaixo sem rolar.
          reverse: true,
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.root case final root?)
                _Root(root: root, onTap: widget.onGoToRoot),
              const SizedBox(height: 18),
              ...switch (state.status) {
                ThreadStatus.loading => [
                  Text('Carregando respostas…', style: muted),
                ],
                ThreadStatus.failed => [
                  Text('Não foi possível carregar as respostas', style: muted),
                  TextButton(
                    onPressed: viewModel.open,
                    child: const Text('Tentar de novo'),
                  ),
                ],
                ThreadStatus.ready => [
                  Text(
                    threadCountLabel(
                      widget.root?.thread?.replies ?? state.replies.length,
                    ),
                    style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                  ),
                  if (!state.reachedStart)
                    state.loadingOlder
                        ? Text('Carregando respostas anteriores…', style: muted)
                        : TextButton(
                            key: const Key('thread_load_older'),
                            onPressed: viewModel.loadOlder,
                            child: const Text('Carregar respostas anteriores'),
                          ),
                  for (final (i, reply) in state.replies.indexed)
                    Padding(
                      key: keyFor(reply.id),
                      padding: const EdgeInsets.only(top: 12),
                      child: MessageHighlight(
                        flashing: flashing == reply.id,
                        child: MessageTile(
                          message: reply,
                          compact: true,
                          followedByOwn:
                              state.replies.elementAtOrNull(i + 1)?.isOwn ??
                              false,
                          onRetry: () => viewModel.retry(reply.id),
                          onCancel: () => viewModel.cancel(reply.id),
                          onReply: () => viewModel.startReply(reply),
                          onQuoteTap: _onQuoteTap,
                        ),
                      ),
                    ),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({required this.root, required this.onTap});

  final MessageItem root;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: 'Ver no canal',
      child: InkWell(
        key: const Key('thread_panel_root'),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: root.senderName,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: root.isOwn ? colors.accent : colors.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: '  ${formatMessageTime(root.timestamp)}',
                      style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 4),
              Text.rich(
                markdownSpan(
                  messageExcerpt(root),
                  style: TextStyle(
                    fontFamily: AppFonts.serif,
                    fontSize: 18,
                    height: 1.5,
                    color: colors.textPrimary,
                  ),
                  codeStyle: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
