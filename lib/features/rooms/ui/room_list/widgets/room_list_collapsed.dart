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
  });

  final RoomListState state;

  final ValueChanged<String> onSelect;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final rooms = state.loaded && state.syncState != SyncState.unsupported
        ? state.visibleRooms
        : const [];
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 20),
            itemCount: rooms.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final room = rooms[index];
              return Center(
                child: RoomAvatarTile(
                  room: room,
                  selected: room.id == state.selectedRoomId,
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
