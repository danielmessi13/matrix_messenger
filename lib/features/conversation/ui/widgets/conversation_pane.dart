import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme.dart';
import '../../../rooms/domain/models/room.dart';
import '../../data/repositories/conversation_repository.dart';
import '../conversation/view_models/conversation_state.dart';
import '../conversation/view_models/conversation_view_model.dart';
import 'conversation_header.dart';
import 'message_input.dart';
import 'timeline_view.dart';

class ConversationPane extends StatelessWidget {
  const ConversationPane({super.key, required this.room, required this.now});

  final Room? room;

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final room = this.room;
    return ColoredBox(
      color: colors.conversationBackground,
      child: switch (room) {
        null => Center(
          child: Text(
            'Selecione uma conversa',
            key: const Key('no_room_selected'),
            style: _italic(colors, 20),
          ),
        ),
        Room(isInvite: true) => Column(
          children: [
            ConversationHeader(room: room),
            Expanded(
              child: Center(
                child: Text(
                  'Você foi convidado para esta sala.',
                  style: _italic(colors, 17),
                ),
              ),
            ),
          ],
        ),
        _ => BlocProvider(
          key: ValueKey(room.id),
          create: (context) => ConversationViewModel(
            context.read<ConversationRepository>(),
            room.id,
          )..open(),
          child: _Conversation(room: room, now: now),
        ),
      },
    );
  }

  static TextStyle _italic(AppColors colors, double size) => TextStyle(
    fontFamily: AppFonts.serif,
    fontStyle: FontStyle.italic,
    fontSize: size,
    color: colors.textMuted,
  );
}

class _Conversation extends StatelessWidget {
  const _Conversation({required this.room, required this.now});

  final Room room;

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.read<ConversationViewModel>();
    final colors = context.colors;
    return Column(
      children: [
        ConversationHeader(room: room),
        Expanded(
          child: BlocBuilder<ConversationViewModel, ConversationState>(
            builder: (context, state) => switch (state.status) {
              ConversationStatus.opening => const Center(
                child: CircularProgressIndicator(),
              ),
              ConversationStatus.failed => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Não foi possível abrir a conversa.',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: viewModel.open,
                      child: const Text('Tentar de novo'),
                    ),
                  ],
                ),
              ),
              ConversationStatus.ready => TimelineView(
                state: state,
                now: now,
                viewModel: viewModel,
              ),
            },
          ),
        ),
        BlocSelector<ConversationViewModel, ConversationState, bool>(
          selector: (state) => state.status == ConversationStatus.ready,
          builder: (context, ready) =>
              MessageInput(room: room, enabled: ready, onSend: viewModel.send),
        ),
      ],
    );
  }
}
