import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/models/timeline_item.dart';
import '../conversation/view_models/conversation_state.dart';
import '../conversation/view_models/conversation_view_model.dart';
import 'focus_flash.dart';
import 'message_labels.dart';
import 'message_tile.dart';
import 'thread_section.dart';

const _loadOlderThreshold = 400.0;

// Distância do fim (em px) a partir da qual o usuário está lendo mensagens antigas.
const _awayFromLatestOffset = 300.0;

class TimelineView extends StatefulWidget {
  const TimelineView({
    super.key,
    required this.state,
    required this.now,
    required this.viewModel,
  });

  final ConversationState state;

  final DateTime now;

  final ConversationViewModel viewModel;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView>
    with FocusFlash<TimelineView> {
  final _scroll = ScrollController();

  bool _awayFromLatest = false;

  bool _unseenNewer = false;

  bool _itemsChangedWhileLoading = false;

  MessageItem? _replyNotice;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillShortHistory());
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    final request = widget.state.focusRequest;
    if (request != null && request != old.state.focusRequest) focusOn(request);
    pruneKeys(widget.state.items.whereType<MessageItem>().map((m) => m.id));
    final items = widget.state.items;
    // A lista some no estado vazio; quando volta, recomeça no fim.
    if (!_scroll.hasClients) {
      _awayFromLatest = false;
      _unseenNewer = false;
      _replyNotice = null;
    }
    if (_awayFromLatest && items.lastOrNull != old.state.items.lastOrNull) {
      _onNewerItems(old);
    }
    final state = widget.state;
    var fill = false;
    if (items != old.state.items) {
      if (state.loadingOlder) {
        _itemsChangedWhileLoading = true;
      } else {
        fill = true;
      }
    }
    if (old.state.loadingOlder &&
        !state.loadingOlder &&
        _itemsChangedWhileLoading) {
      fill = true;
    }
    if (!state.loadingOlder) _itemsChangedWhileLoading = false;
    if (fill) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fillShortHistory());
    }
  }

  void _onNewerItems(TimelineView old) {
    final latest = widget.state.items.whereType<MessageItem>().lastOrNull;
    final oldLatest = old.state.items.whereType<MessageItem>().lastOrNull;
    final newMessage = latest != null && latest.id != oldLatest?.id;
    // Só o envio feito aqui leva ao fim; a minha mensagem vinda de outro aparelho não.
    if (newMessage && latest.sendState == SendState.sending) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToLatest());
      return;
    }
    // Com a rolagem invertida, o item novo entra embaixo e empurra o que está na tela.
    final oldMax = _scroll.position.maxScrollExtent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      _scroll.jumpTo(position.pixels + position.maxScrollExtent - oldMax);
    });
    // A citação pode carregar depois da mensagem e só então revelar que é minha.
    final quoteBecameMine =
        latest != null &&
        latest.id == oldLatest?.id &&
        _unseenNewer &&
        !(oldLatest?.replyTo?.isOwn ?? false);
    if (!newMessage && !quoteBecameMine) return;
    setState(() {
      _unseenNewer = true;
      if (!latest.isOwn && (latest.replyTo?.isOwn ?? false)) {
        _replyNotice = latest;
      }
    });
  }

  void _fillShortHistory() {
    final state = widget.state;
    if (!mounted || !_scroll.hasClients) return;
    if (state.reachedStart || state.loadingOlder) return;
    if (_scroll.position.maxScrollExtent < _loadOlderThreshold) {
      widget.viewModel.loadOlder();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels < _loadOlderThreshold) {
      widget.viewModel.loadOlder();
    }
    final away = position.pixels > _awayFromLatestOffset;
    if (away != _awayFromLatest) {
      setState(() {
        _awayFromLatest = away;
        if (!away) {
          _unseenNewer = false;
          _replyNotice = null;
        }
      });
    }
  }

  void _jumpToLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = widget.state.items;
    if (items.isEmpty && widget.state.reachedStart) {
      return Center(
        child: Text('Nenhuma mensagem ainda.', style: _italic(colors, 17)),
      );
    }
    return Stack(
      children: [
        // Sem lista lazy: toda mensagem carregada fica montada, e dá para rolar até qualquer uma.
        SingleChildScrollView(
          key: const Key('timeline_list'),
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: Column(
            children: [
              _TimelineTop(
                state: widget.state,
                onLoadOlder: widget.viewModel.loadOlder,
              ),
              for (final item in items)
                Center(
                  key: switch (item) {
                    MessageItem(:final id) => keyFor(id),
                    DateDividerItem(:final day) => ValueKey(day),
                  },
                  child: SizedBox(
                    width: 880,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: _TimelineEntry(
                        item: item,
                        now: widget.now,
                        viewModel: widget.viewModel,
                        openThreadId: widget.state.openThreadId,
                        flashing: item is MessageItem && item.id == flashing,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_unseenNewer)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: switch (_replyNotice) {
                final notice? => _ReplyNotice(
                  senderName: notice.senderName,
                  onView: () {
                    setState(() => _replyNotice = null);
                    switch (notice.eventId) {
                      case final eventId?:
                        widget.viewModel.goTo(eventId);
                      case null:
                        _jumpToLatest();
                    }
                  },
                  onDismiss: () => setState(() => _replyNotice = null),
                ),
                null => FilledButton.tonal(
                  key: const Key('jump_to_latest'),
                  onPressed: _jumpToLatest,
                  child: const Text('↓ Mensagens recentes'),
                ),
              },
            ),
          ),
      ],
    );
  }
}

class _TimelineTop extends StatelessWidget {
  const _TimelineTop({required this.state, required this.onLoadOlder});

  final ConversationState state;

  final VoidCallback onLoadOlder;

  @override
  Widget build(BuildContext context) {
    if (state.reachedStart) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: Text(
            'Início da conversa',
            style: _italic(context.colors, 15),
          ),
        ),
      );
    }
    if (!state.loadingOlder) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Center(
          child: TextButton(
            key: const Key('timeline_load_older'),
            onPressed: onLoadOlder,
            child: const Text('Carregar anteriores'),
          ),
        ),
      );
    }
    return const Padding(
      key: Key('timeline_loading_older'),
      padding: EdgeInsets.all(12),
      child: Center(
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.item,
    required this.now,
    required this.viewModel,
    required this.openThreadId,
    required this.flashing,
  });

  final TimelineItem item;

  final DateTime now;

  final ConversationViewModel viewModel;

  final String? openThreadId;

  final bool flashing;

  @override
  Widget build(BuildContext context) => switch (item) {
    DateDividerItem(:final day) => Center(
      child: Text(
        formatDayDivider(day, now),
        style: _italic(context.colors, 17),
      ),
    ),
    final MessageItem message => MessageHighlight(
      flashing: flashing,
      open: message.eventId != null && message.eventId == openThreadId,
      child: MessageTile(
        message: message,
        onRetry: () => viewModel.retry(message.id),
        onCancel: () => viewModel.cancel(message.id),
        onReply: () => viewModel.startReply(message),
        // "Thread" só para quem ainda não tem uma e não está aberta.
        onStartThread: switch (message.eventId) {
          final eventId?
              when message.thread == null && openThreadId != eventId =>
            () => viewModel.openThread(eventId),
          _ => null,
        },
        onQuoteTap: viewModel.goTo,
        thread: switch ((message.thread, message.eventId)) {
          (final summary?, _) => ThreadSection(
            rootEventId: summary.rootEventId,
            summary: summary,
            open: openThreadId == summary.rootEventId,
            onTap: () => viewModel.toggleThread(summary.rootEventId),
          ),
          (null, final eventId?) when openThreadId == eventId => ThreadSection(
            rootEventId: eventId,
            open: true,
            onTap: viewModel.closeThread,
          ),
          _ => null,
        },
      ),
    ),
  };
}

class _ReplyNotice extends StatelessWidget {
  const _ReplyNotice({
    required this.senderName,
    required this.onView,
    required this.onDismiss,
  });

  final String senderName;

  final VoidCallback onView;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: colors.background,
    );
    return Material(
      key: const Key('reply_notice'),
      color: colors.accent,
      elevation: 6,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const Key('reply_notice_view'),
            onTap: onView,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 6, 8),
              child: Text(
                '↩ ${repliedToYouLabel(senderName)} · Ver',
                style: style,
              ),
            ),
          ),
          InkWell(
            key: const Key('reply_notice_dismiss'),
            onTap: onDismiss,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
              child: Text('×', style: style.copyWith(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle _italic(AppColors colors, double size) => TextStyle(
  fontFamily: AppFonts.serif,
  fontStyle: FontStyle.italic,
  fontSize: size,
  color: colors.textMuted,
);
