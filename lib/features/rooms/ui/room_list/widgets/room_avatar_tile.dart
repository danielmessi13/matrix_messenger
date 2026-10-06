import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../domain/models/room.dart';
import 'room_labels.dart';

class RoomAvatarTile extends StatelessWidget {
  const RoomAvatarTile({
    super.key,
    required this.room,
    required this.selected,
    required this.unread,
    required this.onTap,
    this.tooltip,
  });

  final Room room;

  final bool selected;

  final int unread;

  final VoidCallback onTap;

  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip ?? roomName(room),
      child: InkWell(
        key: Key('room_avatar_${room.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
                border: selected
                    ? Border.all(color: colors.accent, width: 2)
                    : null,
              ),
              child: Text(
                roomInitials(room),
                style: TextStyle(
                  fontFamily: AppFonts.serif,
                  fontSize: 18,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (unread > 0)
              Positioned(
                right: -5,
                top: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.listBackground, width: 2),
                  ),
                  child: Text(
                    '$unread',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: colors.background,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
