import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../../../core/services/image_file_picker.dart';
import '../../../rooms/data/repositories/room_repository.dart';
import '../../../rooms/domain/models/room.dart';
import '../../../rooms/domain/models/thread_request.dart';
import '../../../rooms/ui/invite/view_models/invite_view_model.dart';
import '../../../rooms/ui/invite/widgets/invite_actions.dart';
import '../../../rooms/ui/room_list/view_models/message_search_state.dart';
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
    this.focus,
    this.threadRequest,
    this.onThreadOpenChanged,
    this.onOpenThreadChanged,
  });

  final Room? room;

  final DateTime now;

  final EventFocus? focus;

  final ThreadRequest? threadRequest;

  // A home recolhe a lista de salas para a thread caber ao lado.
  final ValueChanged<bool>? onThreadOpenChanged;

  // A lista de threads recentes destaca a thread aberta.
  final ValueChanged<String?>? onOpenThreadChanged;

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
          child: _FocusOnEvent(
            focus: focus,
            child: _ThreadVisibility(
              onChanged: onThreadOpenChanged,
              onThreadChanged: onOpenThreadChanged,
              child: _ThreadRequestListener(
                request: threadRequest?.roomId == room.id
                    ? threadRequest
                    : null,
                child: _Conversation(room: room, now: now),
              ),
            ),
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

class _FocusOnEvent extends StatefulWidget {
  const _FocusOnEvent({required this.focus, required this.child});

  final EventFocus? focus;

  final Widget child;

  @override
  State<_FocusOnEvent> createState() => _FocusOnEventState();
}

class _FocusOnEventState extends State<_FocusOnEvent> {
  @override
  void initState() {
    super.initState();
    _focus();
  }

  @override
  void didUpdateWidget(_FocusOnEvent old) {
    super.didUpdateWidget(old);
    if (widget.focus != old.focus) _focus();
  }

  void _focus() {
    final eventId = widget.focus?.eventId;
    if (eventId != null) {
      context.read<ConversationViewModel>().focusEvent(eventId);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ThreadRequestListener extends StatefulWidget {
  const _ThreadRequestListener({required this.request, required this.child});

  final ThreadRequest? request;

  final Widget child;

  @override
  State<_ThreadRequestListener> createState() => _ThreadRequestListenerState();
}

class _ThreadRequestListenerState extends State<_ThreadRequestListener> {
  @override
  void initState() {
    super.initState();
    _open(widget.request);
  }

  @override
  void didUpdateWidget(_ThreadRequestListener old) {
    super.didUpdateWidget(old);
    if (!identical(old.request, widget.request)) _open(widget.request);
  }

  void _open(ThreadRequest? request) {
    if (request == null) return;
    context.read<ConversationViewModel>().openThread(request.rootEventId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ThreadVisibility extends StatefulWidget {
  const _ThreadVisibility({
    required this.onChanged,
    required this.onThreadChanged,
    required this.child,
  });

  final ValueChanged<bool>? onChanged;

  final ValueChanged<String?>? onThreadChanged;

  final Widget child;

  @override
  State<_ThreadVisibility> createState() => _ThreadVisibilityState();
}

class _ThreadVisibilityState extends State<_ThreadVisibility> {
  bool _open = false;

  @override
  void dispose() {
    final onChanged = widget.onChanged;
    final onThreadChanged = widget.onThreadChanged;
    // Trocar de sala com a thread aberta também a fecha; avisa fora da desmontagem.
    if (_open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged?.call(false);
        onThreadChanged?.call(null);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<ConversationViewModel, ConversationState>(
        listenWhen: (a, b) => a.openThreadId != b.openThreadId,
        listener: (context, state) {
          final open = state.openThreadId != null;
          if (open != _open) widget.onChanged?.call(open);
          _open = open;
          widget.onThreadChanged?.call(state.openThreadId);
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
        BlocConsumer<ConversationViewModel, ConversationState>(
          listenWhen: (a, b) => a.imageSend != b.imageSend,
          listener: (context, state) {
            final message = switch (state.imageSend) {
              ImageSendStatus.invalid =>
                'O arquivo não é uma imagem PNG, JPEG, GIF ou WebP.',
              ImageSendStatus.failed => 'Não foi possível enviar a imagem.',
              ImageSendStatus.idle || ImageSendStatus.sending => null,
            };
            if (message == null) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          },
          buildWhen: (a, b) =>
              a.status != b.status ||
              a.replyTo != b.replyTo ||
              a.imageSend != b.imageSend ||
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
            onAttachImage: () => _attachImage(context, viewModel),
            attaching: state.imageSend == ImageSendStatus.sending,
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

Future<void> _attachImage(
  BuildContext context,
  ConversationViewModel viewModel,
) async {
  final path = await context.read<ImageFilePicker>().pickImage();
  if (path != null) await viewModel.sendImage(path);
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
