import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../rooms/domain/models/room.dart';
import '../../../rooms/ui/invite_room/widgets/invite_room_button.dart';
import '../../../rooms/ui/leave_room/widgets/leave_room_button.dart';
import '../../../rooms/ui/room_link/widgets/copy_room_link_button.dart';
import '../../../rooms/ui/room_list/widgets/room_labels.dart';

class ConversationHeader extends StatelessWidget {
  const ConversationHeader({
    super.key,
    required this.room,
    required this.ownUserId,
  });

  final Room room;

  final String ownUserId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canCopyLink = room.isPublic && !room.isDirect;
    final isJoinedRoom = !room.isInvite && !room.isDirect;
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roomMetaLabel(room),
                      style: TextStyle(
                        fontSize: 12.5,
                        letterSpacing: 1,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      roomTitle(room),
                      key: const Key('conversation_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontSize: 44,
                        height: 1,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              if (canCopyLink || isJoinedRoom) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    if (canCopyLink)
                      CopyRoomLinkButton(
                        key: ValueKey(room.id),
                        roomId: room.id,
                      ),
                    if (isJoinedRoom) ...[
                      InviteRoomButton(
                        key: ValueKey('invite_${room.id}'),
                        roomId: room.id,
                        roomName: roomTitle(room),
                        ownUserId: ownUserId,
                      ),
                      LeaveRoomButton(
                        key: ValueKey('leave_${room.id}'),
                        roomId: room.id,
                        roomName: roomTitle(room),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 12),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final hero in room.heroes.take(4))
                    Align(
                      widthFactor: 0.75,
                      child: Tooltip(
                        message: hero,
                        child: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.surfaceHigh,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colors.conversationBackground,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            initialsOfName(hero),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
