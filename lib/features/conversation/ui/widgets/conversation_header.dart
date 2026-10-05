import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../rooms/domain/models/room.dart';
import '../../../rooms/ui/room_list/widgets/room_labels.dart';

class ConversationHeader extends StatelessWidget {
  const ConversationHeader({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
