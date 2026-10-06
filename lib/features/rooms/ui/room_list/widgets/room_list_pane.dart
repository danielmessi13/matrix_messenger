import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/ui/animated_pane.dart';
import '../../../domain/models/message_hit.dart';
import '../view_models/room_list_state.dart';
import 'room_list_collapsed.dart';
import 'room_list_expanded.dart';

const kRoomListWidth = 480.0;

const kRoomListCompactWidth = 84.0;

class RoomListPane extends StatelessWidget {
  const RoomListPane({
    super.key,
    required this.expanded,
    required this.state,
    required this.now,
    required this.onSelect,
    required this.onToggle,
    required this.onOpenMessage,
    required this.onLoadMoreMessages,
    required this.onRetryMessages,
  });

  final bool expanded;

  final RoomListState state;

  final DateTime now;

  final ValueChanged<String> onSelect;

  final VoidCallback onToggle;

  final ValueChanged<MessageHit> onOpenMessage;

  final VoidCallback onLoadMoreMessages;

  final VoidCallback onRetryMessages;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final hidden = !expanded && state.loaded && state.visibleRooms.isEmpty;

    return AnimatedPane(
      expanded: expanded,
      hidden: hidden,
      expandedWidth: kRoomListWidth,
      compactWidth: kRoomListCompactWidth,
      decoration: BoxDecoration(
        color: colors.listBackground,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      expandedChild: RoomListExpanded(
        state: state,
        now: now,
        onSelect: onSelect,
        onToggle: onToggle,
        onOpenMessage: onOpenMessage,
        onLoadMoreMessages: onLoadMoreMessages,
        onRetryMessages: onRetryMessages,
      ),
      compactChild: RoomListCollapsed(
        state: state,
        onSelect: onSelect,
        onToggle: onToggle,
      ),
    );
  }
}
