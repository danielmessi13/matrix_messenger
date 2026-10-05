import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../rooms/domain/models/room.dart';
import '../../../rooms/ui/room_list/widgets/room_labels.dart';

class MessageInput extends StatelessWidget {
  const MessageInput({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Container(
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.borderStrong),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  enabled: false,
                  minLines: 2,
                  maxLines: 2,
                  style: const TextStyle(
                    fontFamily: AppFonts.serif,
                    fontSize: 19,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Escrever para ${roomTitle(room)}…',
                    hintStyle: TextStyle(
                      fontFamily: AppFonts.serif,
                      fontSize: 19,
                      color: colors.textMuted,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Enter envia · Shift + Enter nova linha',
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const FilledButton(onPressed: null, child: Text('Enviar')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
