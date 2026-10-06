import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../domain/models/room.dart';
import 'room_labels.dart';

class RoomTile extends StatelessWidget {
  const RoomTile({
    super.key,
    required this.room,
    required this.selected,
    required this.unread,
    required this.now,
    required this.onTap,
  });

  final Room room;

  final bool selected;

  final int unread;

  final DateTime now;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final latest = room.latest;
    return Material(
      color: selected ? colors.selectedRow : Colors.transparent,
      child: InkWell(
        key: Key('room_${room.id}'),
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
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      roomListLabel(room),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontSize: 21,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (unread > 0) ...[
                    Text(
                      unreadLabel(unread),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (room.isInvite)
                    const _InviteTag()
                  else if (latest != null)
                    Text(
                      formatRoomTime(latest.timestamp, now),
                      style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                latestPreview(room),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteTag extends StatelessWidget {
  const _InviteTag();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: colors.accent),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Convite',
        style: TextStyle(fontSize: 11.5, color: colors.accent),
      ),
    );
  }
}
