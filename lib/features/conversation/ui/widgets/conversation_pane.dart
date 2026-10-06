import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../../rooms/data/repositories/room_repository.dart';
import '../../../rooms/domain/models/room.dart';
import '../../../rooms/ui/invite/view_models/invite_view_model.dart';
import '../../../rooms/ui/invite/widgets/invite_actions.dart';
import '../../../rooms/ui/room_list/widgets/room_labels.dart';
import '../../data/repositories/conversation_repository.dart';
import '../../domain/models/timeline_item.dart';
import '../conversation/view_models/conversation_state.dart';
import '../conversation/view_models/conversation_view_model.dart';
import 'conversation_header.dart';
import 'delayed_indicator.dart';
import 'message_input.dart';
import 'message_labels.dart';
import 'thread_panel.dart';
import 'timeline_view.dart';

// Abaixo disto o painel da thread fica por cima da conversa.
const kThreadSideBySideWidth = 1000.0;

class ConversationPane extends StatelessWidget {
  const ConversationPane({
    super.key,
    required this.room,
    required this.now,
    this.onThreadOpenChanged,
  });

  final Room? room;

  final DateTime now;

  // A home recolhe a lista de salas para a thread caber ao lado.
  final ValueChanged<bool>? onThreadOpenChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final room = this.room;
    return ColoredBox(
      color: colors.conversationBackground,
      child: switch (room) {
        null => Center(
          child: Text(
            'Selecione uma conversa',
            key: const Key('no_room_selected'),
            style: _italic(colors, 20),
          ),
        ),
        Room(isInvite: true) => Column(
          children: [
            ConversationHeader(room: room),
            Expanded(
              child: Center(
                child: BlocProvider(
                  key: ValueKey(room.id),
                  create: (context) =>
                      InviteViewModel(context.read<RoomRepository>(), room.id),
                  child: const InviteActions(),
                ),
              ),
            ),
          ],
        ),
        _ => BlocProvider(
          key: ValueKey(room.id),
          create: (context) => ConversationViewModel(
            context.read<ConversationRepository>(),
            room.id,
          )..open(),
          child: _ThreadVisibility(
            onChanged: onThreadOpenChanged,
            child: _Conversation(room: room, now: now),
          ),
        ),
      },
    );
  }

  static TextStyle _italic(AppColors colors, double size) => TextStyle(
    fontFamily: AppFonts.serif,
    fontStyle: FontStyle.italic,
    fontSize: size,
    color: colors.textMuted,
  );
}

class _ThreadVisibility extends StatefulWidget {
  const _ThreadVisibility({required this.onChanged, required this.child});

  final ValueChanged<bool>? onChanged;

  final Widget child;

  @override
  State<_ThreadVisibility> createState() => _ThreadVisibilityState();
}

class _ThreadVisibilityState extends State<_ThreadVisibility> {
  bool _open = false;

  @override
  void dispose() {
    final onChanged = widget.onChanged;
    // Trocar de sala com a thread aberta também a fecha; avisa fora da desmontagem.
    if (_open && onChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<ConversationViewModel, ConversationState>(
        listenWhen: (a, b) =>
            (a.openThreadId == null) != (b.openThreadId == null),
        listener: (context, state) {
          _open = state.openThreadId != null;
          widget.onChanged?.call(_open);
        },
        child: widget.child,
      );
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.room, required this.now});

  final Room room;

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<ConversationViewModel>();
    final colors = context.colors;
    final conversation = Column(
      children: [
        ConversationHeader(room: room),
        Expanded(
          child: BlocBuilder<ConversationViewModel, ConversationState>(
            builder: (context, state) => switch (state.status) {
              ConversationStatus.opening => const Center(
                child: DelayedIndicator(child: CircularProgressIndicator()),
              ),
              ConversationStatus.failed => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Não foi possível abrir a conversa.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: viewModel.open,
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
              ConversationStatus.ready => TimelineView(
                state: state,
                now: now,
                viewModel: viewModel,
              ),
            },
          ),
        ),
        BlocBuilder<ConversationViewModel, ConversationState>(
          buildWhen: (a, b) =>
              a.status != b.status ||
              a.replyTo != b.replyTo ||
              (a.openThreadId == null) != (b.openThreadId == null),
          builder: (context, state) => MessageInput(
            placeholder: composerHint(
              roomTitle: roomTitle(room),
              replyTo: state.replyTo,
            ),
            replyTo: state.replyTo,
            onCancelReply: viewModel.cancelReply,
            enabled: state.status == ConversationStatus.ready,
            covered: state.openThreadId != null,
            onSend: viewModel.send,
            onChanged: viewModel.onDraftChanged,
            status: const _TypingLine(),
          ),
        ),
      ],
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): viewModel.escape,
      },
      child: BlocSelector<ConversationViewModel, ConversationState, String?>(
        selector: (state) => state.openThreadId,
        builder: (context, openThreadId) {
          final thread = viewModel.thread;
          final open = openThreadId != null && thread != null;
          final panel = !open
              ? null
              : BlocSelector<
                  ConversationViewModel,
                  ConversationState,
                  MessageItem?
                >(
                  selector: (state) => state.items
                      .whereType<MessageItem>()
                      .where((message) => message.eventId == openThreadId)
                      .firstOrNull,
                  builder: (context, root) => ThreadPanel(
                    key: ValueKey(openThreadId),
                    room: room,
                    rootEventId: openThreadId,
                    root: root,
                    viewModel: thread,
                    onClose: viewModel.closeThread,
                    onGoToRoot: () => viewModel.goTo(openThreadId),
                  ),
                );
          // Mesma posição na árvore nos três casos, para a conversa não perder rolagem nem rascunho.
          return LayoutBuilder(
            builder: (context, box) {
              final sideBySide = box.maxWidth >= kThreadSideBySideWidth;
              return Stack(
                children: [
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    right: open && sideBySide ? threadPanelWidth : 0,
                    child: conversation,
                  ),
                  if (panel != null)
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      width: min(threadPanelWidth, box.maxWidth),
                      child: Material(
                        elevation: sideBySide ? 0 : 8,
                        child: panel,
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// Altura fixa: aparecer e sumir não empurra a timeline.
class _TypingLine extends StatelessWidget {
  const _TypingLine();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 24,
      child: BlocSelector<ConversationViewModel, ConversationState, String>(
        selector: (state) => typingLabel(state.typing),
        builder: (context, label) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: label.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  key: const Key('typing_indicator'),
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.serif,
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                      color: colors.textMuted,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
