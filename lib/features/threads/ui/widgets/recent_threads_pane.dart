import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../core/ui/animated_pane.dart';
import '../../../../core/ui/pane_toggle_button.dart';
import '../../../rooms/domain/models/room.dart';
import '../../../rooms/ui/room_list/widgets/room_avatar_tile.dart';
import '../../../rooms/ui/room_list/widgets/room_labels.dart';
import '../../../rooms/ui/room_list/widgets/room_list_pane.dart';
import '../../domain/models/recent_thread.dart';
import '../view_models/recent_threads_state.dart';
import 'recent_thread_labels.dart';

class RecentThreadsPane extends StatelessWidget {
  const RecentThreadsPane({
    super.key,
    required this.expanded,
    required this.state,
    required this.rooms,
    required this.selectedRoomId,
    this.openThreadId,
    required this.now,
    required this.onSelect,
    required this.onRetry,
    required this.onToggle,
    this.header,
    this.compactHeader,
  });

  final bool expanded;

  final RecentThreadsState state;

  final List<Room> rooms;

  final String? selectedRoomId;

  final String? openThreadId;

  final DateTime now;

  final ValueChanged<RecentThread> onSelect;

  final VoidCallback onRetry;

  final VoidCallback onToggle;

  final Widget? header;

  final Widget? compactHeader;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final byId = {for (final room in rooms) room.id: room};
    // Thread de sala que saiu da lista não tem como abrir.
    final entries = [
      for (final thread in state.threads)
        if (byId[thread.roomId] case final room?)
          (
            thread: thread,
            room: room,
            selected:
                room.id == selectedRoomId && thread.rootEventId == openThreadId,
          ),
    ];
    return AnimatedPane(
      expanded: expanded,
      expandedWidth: kRoomListWidth,
      compactWidth: kRoomListCompactWidth,
      decoration: BoxDecoration(
        color: colors.listBackground,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      expandedChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onToggle: onToggle),
          ?header,
          Expanded(
            child: _Body(
              status: state.status,
              entries: entries,
              now: now,
              onSelect: onSelect,
              onRetry: onRetry,
            ),
          ),
        ],
      ),
      compactChild: _Collapsed(
        entries: entries,
        onSelect: onSelect,
        onToggle: onToggle,
        header: compactHeader,
      ),
    );
  }
}

typedef _Entry = ({RecentThread thread, Room room, bool selected});

class _Header extends StatelessWidget {
  const _Header({required this.onToggle});

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
              'Threads recentes',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontSize: 32,
                color: colors.textPrimary,
              ),
            ),
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
}

class _Body extends StatelessWidget {
  const _Body({
    required this.status,
    required this.entries,
    required this.now,
    required this.onSelect,
    required this.onRetry,
  });

  final RecentThreadsStatus status;

  final List<_Entry> entries;

  final DateTime now;

  final ValueChanged<RecentThread> onSelect;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (entries.isEmpty) {
      return switch (status) {
        RecentThreadsStatus.loading => const Center(
          child: CircularProgressIndicator(key: Key('recent_threads_loading')),
        ),
        RecentThreadsStatus.failed => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Não foi possível carregar as threads',
                style: TextStyle(fontSize: 14.5, color: colors.textMuted),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('recent_threads_retry'),
                onPressed: onRetry,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
        RecentThreadsStatus.ready => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Text(
            'Nenhuma thread recente',
            style: TextStyle(fontSize: 14.5, color: colors.textMuted),
          ),
        ),
      };
    }
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _ThreadTile(
          thread: entry.thread,
          room: entry.room,
          selected: entry.selected,
          now: now,
          onTap: () => onSelect(entry.thread),
        );
      },
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.room,
    required this.selected,
    required this.now,
    required this.onTap,
  });

  final RecentThread thread;

  final Room room;

  final bool selected;

  final DateTime now;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final latest = threadLatestPreview(thread);
    return Material(
      color: selected ? colors.selectedRow : Colors.transparent,
      child: InkWell(
        key: Key('thread_${thread.roomId}_${thread.rootEventId}'),
        onTap: onTap,
        hoverColor: colors.hoverRow,
        child: Container(
          padding: const EdgeInsets.fromLTRB(25, 14, 28, 14),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? colors.accent : Colors.transparent,
                width: 3,
              ),
              bottom: BorderSide(color: colors.rowDivider),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      roomListLabel(room),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatRoomTime(thread.activity, now),
                    style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                threadRootPreview(thread.root),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 18,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                threadActivityLabel(thread),
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
              if (latest.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  latest,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Collapsed extends StatelessWidget {
  const _Collapsed({
    required this.entries,
    required this.onSelect,
    required this.onToggle,
    this.header,
  });

  final List<_Entry> entries;

  final ValueChanged<RecentThread> onSelect;

  final VoidCallback onToggle;

  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final offset = header == null ? 0 : 1;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 20),
            itemCount: entries.length + offset,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (header != null && index == 0) return Center(child: header);
              final (:thread, :room, :selected) = entries[index - offset];
              return Center(
                child: KeyedSubtree(
                  key: Key(
                    'thread_avatar_${thread.roomId}_${thread.rootEventId}',
                  ),
                  child: RoomAvatarTile(
                    room: room,
                    selected: selected,
                    unread: 0,
                    onTap: () => onSelect(thread),
                    tooltip:
                        '${roomListLabel(room)}\n${threadRootPreview(thread.root)}',
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: PaneToggleButton(
            key: const Key('toggle_room_list'),
            pointsLeft: false,
            tooltip: 'Expandir lista',
            onPressed: onToggle,
          ),
        ),
      ],
    );
  }
}
