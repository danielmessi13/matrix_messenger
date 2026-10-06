import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../domain/models/timeline_item.dart';
import '../conversation/view_models/conversation_state.dart';
import '../conversation/view_models/conversation_view_model.dart';
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

class _TimelineViewState extends State<TimelineView> {
  final _scroll = ScrollController();

  bool _awayFromLatest = false;

  bool _unseenNewer = false;

  bool _itemsChangedWhileLoading = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fillShortHistory());
  }

  @override
  void didUpdateWidget(TimelineView old) {
    super.didUpdateWidget(old);
    final items = widget.state.items;
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
    // Na lista invertida o item novo entra no índice 0 e empurra o que está na tela.
    final oldMax = _scroll.position.maxScrollExtent;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      _scroll.jumpTo(position.pixels + position.maxScrollExtent - oldMax);
    });
    if (newMessage) setState(() => _unseenNewer = true);
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
        if (!away) _unseenNewer = false;
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
    final items = widget.state.items.reversed.toList();
    if (items.isEmpty && widget.state.reachedStart) {
      return Center(
        child: Text('Nenhuma mensagem ainda.', style: _italic(colors, 17)),
      );
    }
    return Stack(
      children: [
        ListView.builder(
          key: const Key('timeline_list'),
          controller: _scroll,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == items.length) return _top(colors);
            return Center(
              key: switch (items[index]) {
                MessageItem(:final id) => ValueKey(id),
                DateDividerItem(:final day) => ValueKey(day),
              },
              child: SizedBox(
                width: 880,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: _item(items[index], colors),
                ),
              ),
            );
          },
        ),
        if (_unseenNewer)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.tonal(
                key: const Key('jump_to_latest'),
                onPressed: _jumpToLatest,
                child: const Text('↓ Mensagens recentes'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _top(AppColors colors) {
    if (widget.state.reachedStart) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Center(
          child: Text('Início da conversa', style: _italic(colors, 15)),
        ),
      );
    }
    if (!widget.state.loadingOlder) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Center(
          child: TextButton(
            key: const Key('timeline_load_older'),
            onPressed: widget.viewModel.loadOlder,
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

  Widget _item(TimelineItem item, AppColors colors) => switch (item) {
    DateDividerItem(:final day) => Center(
      child: Text(
        formatDayDivider(day, widget.now),
        style: _italic(colors, 17),
      ),
    ),
    MessageItem() => MessageTile(
      message: item,
      onRetry: () => widget.viewModel.retry(item.id),
      onCancel: () => widget.viewModel.cancel(item.id),
      thread: switch (item.thread) {
        null => null,
        final thread => ThreadSection(
          summary: thread,
          viewModel: widget.viewModel.thread(thread.rootEventId),
          onToggle: () => widget.viewModel.toggleThread(thread.rootEventId),
        ),
      },
    ),
  };

  static TextStyle _italic(AppColors colors, double size) => TextStyle(
    fontFamily: AppFonts.serif,
    fontStyle: FontStyle.italic,
    fontSize: size,
    color: colors.textMuted,
  );
}
