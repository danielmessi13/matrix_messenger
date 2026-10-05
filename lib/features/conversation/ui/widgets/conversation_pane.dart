import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../rooms/domain/models/room.dart';
import 'conversation_header.dart';
import 'message_input.dart';

class ConversationPane extends StatelessWidget {
  const ConversationPane({super.key, required this.room});

  final Room? room;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final room = this.room;
    return ColoredBox(
      color: colors.conversationBackground,
      child: room == null
          ? Center(
              child: Text(
                'Selecione uma conversa',
                key: const Key('no_room_selected'),
                style: _italic(colors, 20),
              ),
            )
          : Column(
              children: [
                ConversationHeader(room: room),
                Expanded(
                  child: Center(
                    child: Text(
                      'As mensagens desta conversa aparecerão aqui.',
                      style: _italic(colors, 17),
                    ),
                  ),
                ),
                MessageInput(room: room),
              ],
            ),
    );
  }

  static TextStyle _italic(AppColors colors, double size) => TextStyle(
    fontFamily: AppFonts.serif,
    fontStyle: FontStyle.italic,
    fontSize: size,
    color: colors.textMuted,
  );
}
