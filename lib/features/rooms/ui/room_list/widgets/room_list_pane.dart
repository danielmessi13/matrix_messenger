import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../view_models/room_list_state.dart';
import 'room_list_collapsed.dart';
import 'room_list_expanded.dart';

class RoomListPane extends StatelessWidget {
  const RoomListPane({
    super.key,
    required this.expanded,
    required this.state,
    required this.now,
    required this.onSelect,
    required this.onToggle,
  });

  final bool expanded;

  final RoomListState state;

  final DateTime now;

  final ValueChanged<String> onSelect;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: expanded ? 480 : 84,
      decoration: BoxDecoration(
        color: colors.listBackground,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: expanded
          ? RoomListExpanded(
              state: state,
              now: now,
              onSelect: onSelect,
              onToggle: onToggle,
            )
          : RoomListCollapsed(
              state: state,
              onSelect: onSelect,
              onToggle: onToggle,
            ),
    );
  }
}
