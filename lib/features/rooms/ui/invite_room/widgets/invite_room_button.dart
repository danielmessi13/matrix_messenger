import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../app/theme.dart';
import '../../../data/repositories/room_repository.dart';
import '../../invite_chips/view_models/invite_chips_view_model.dart';
import '../view_models/can_invite_view_model.dart';
import '../view_models/invite_room_view_model.dart';
import 'invite_room_dialog.dart';

class InviteRoomButton extends StatelessWidget {
  const InviteRoomButton({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.ownUserId,
  });

  final String roomId;

  final String roomName;

  final String ownUserId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) =>
        CanInviteViewModel(context.read<RoomRepository>(), roomId)..load(),
    child: BlocBuilder<CanInviteViewModel, bool>(
      builder: (context, allowed) {
        if (!allowed) return const SizedBox.shrink();
        return IconButton(
          key: const Key('invite_room'),
          tooltip: 'Convidar',
          iconSize: 18,
          color: context.colors.textSecondary,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          onPressed: () {
            final repository = context.read<RoomRepository>();
            showDialog<void>(
              context: context,
              builder: (_) => MultiBlocProvider(
                providers: [
                  BlocProvider(
                    create: (_) => InviteRoomViewModel(repository, roomId),
                  ),
                  BlocProvider(
                    create: (_) => InviteChipsViewModel(
                      repository,
                      exclude: {ownUserId},
                    ),
                  ),
                ],
                child: InviteRoomDialog(roomName: roomName),
              ),
            );
          },
        );
      },
    ),
  );
}
