import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/ui/pane_toggle_button.dart';
import '../../../domain/models/message_hit.dart';
import '../../../domain/models/sync_state.dart';
import '../view_models/message_search_state.dart';
import '../view_models/room_list_state.dart';
import 'message_results.dart';
import 'room_labels.dart';
import 'room_tile.dart';

class RoomListExpanded extends StatelessWidget {
  const RoomListExpanded({
    super.key,
    required this.state,
    required this.now,
    required this.onSelect,
    required this.onToggle,
    required this.onOpenMessage,
    required this.onLoadMoreMessages,
    required this.onRetryMessages,
    this.header,
  });

  final RoomListState state;

  final DateTime now;

  final ValueChanged<String> onSelect;

  final VoidCallback onToggle;

  final ValueChanged<MessageHit> onOpenMessage;

  final VoidCallback onLoadMoreMessages;

  final VoidCallback onRetryMessages;

  final Widget? header;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Header(state: state, onToggle: onToggle),
      if (_bannerText() case final text?) _SyncBanner(text: text),
      ?header,
      Expanded(
        child: state.searching
            ? MessageResults(
                search: state.messages,
                query: state.query,
                now: now,
                onOpen: onOpenMessage,
                onLoadMore: onLoadMoreMessages,
                onRetry: onRetryMessages,
              )
            : _Body(state: state, now: now, onSelect: onSelect),
      ),
    ],
  );

  String? _bannerText() => switch (state.syncState) {
    SyncState.offline => 'Sem conexão — mostrando dados salvos',
    SyncState.error => 'Problema ao sincronizar. Tentando novamente…',
    _ => null,
  };
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.onToggle});

  final RoomListState state;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              state.searching ? 'Resultados' : state.filter.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontSize: 32,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (state.loaded || state.searching)
            Text(
              _subtitle(),
              style: TextStyle(fontSize: 13, color: colors.textMuted),
            ),
          const SizedBox(width: 14),
          PaneToggleButton(
            key: const Key('toggle_room_list'),
            pointsLeft: true,
            tooltip: 'Minimizar lista',
            onPressed: onToggle,
            size: 26,
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    if (state.searching) {
      final messages = state.messages;
      if (messages.status != MessageSearchStatus.ready) return '';
      final count = messages.hits.length;
      final more = messages.hasMore ? '+' : '';
      return '$count$more ${count == 1 && more.isEmpty ? 'mensagem' : 'mensagens'}';
    }
    final unread = state.visibleUnread;
    if (unread == 0) return 'Tudo em dia';
    return '$unread ${unread == 1 ? 'não lida' : 'não lidas'}';
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.text})
    : super(key: const Key('sync_banner'));

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      color: colors.surface,
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: colors.textSecondary),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state, required this.now, required this.onSelect});

  final RoomListState state;

  final DateTime now;

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (state.syncState == SyncState.unsupported) {
      return const _Message(
        key: Key('sync_unsupported'),
        text: 'Este servidor não suporta a sincronização usada pelo app.',
      );
    }
    if (!state.loaded) {
      return ListView(
        children: [for (var i = 0; i < 6; i++) const _SkeletonTile()],
      );
    }
    final rooms = state.visibleRooms;
    if (rooms.isEmpty) {
      return const _Message(text: 'Nenhuma conversa encontrada.');
    }
    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        return RoomTile(
          room: room,
          selected: room.id == state.selectedRoomId,
          unread: state.filter.unreadOf(room),
          now: now,
          onTap: () => onSelect(room.id),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
    child: Text(
      text,
      style: TextStyle(fontSize: 14.5, color: context.colors.textMuted),
    ),
  );
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('room_skeleton'),
    padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.rowDivider)),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SkeletonBar(width: 180, height: 16),
        SizedBox(height: 10),
        _SkeletonBar(width: 300, height: 12),
      ],
    ),
  );
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.width, required this.height});

  final double width;

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
