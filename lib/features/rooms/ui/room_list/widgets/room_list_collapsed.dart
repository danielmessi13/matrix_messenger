import 'package:flutter/material.dart';

import '../../../../../core/ui/pane_toggle_button.dart';
import '../../../domain/models/sync_state.dart';
import '../view_models/room_list_state.dart';
import 'room_avatar_tile.dart';

class RoomListCollapsed extends StatelessWidget {
  const RoomListCollapsed({
    super.key,
    required this.state,
    required this.onSelect,
    required this.onToggle,
    this.compactHeader,
  });

  final RoomListState state;

  final ValueChanged<String> onSelect;

  final VoidCallback onToggle;

  final Widget? compactHeader;

  @override
  Widget build(BuildContext context) {
    final rooms = state.loaded && state.syncState != SyncState.unsupported
        ? state.visibleRooms
        : const [];
    final header = compactHeader;
    final offset = header == null ? 0 : 1;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 20),
            itemCount: rooms.length + offset,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (header != null && index == 0) return Center(child: header);
              final room = rooms[index - offset];
              return Center(
                child: RoomAvatarTile(
                  room: room,
                  selected: room.id == state.selectedRoomId,
                  unread: state.filter.unreadOf(room),
                  onTap: () => onSelect(room.id),
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
