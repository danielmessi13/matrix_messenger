import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/room_action_failure.dart';
import 'invite_room_state.dart';

class InviteRoomViewModel extends Cubit<InviteRoomState> {
  InviteRoomViewModel(this._repository, this._roomId)
    : super(const InviteRoomState());

  final RoomRepository _repository;

  final String _roomId;

  Future<void> send(List<String> userIds) async {
    if (isClosed || state.sending || userIds.isEmpty) return;
    emit(const InviteRoomState(status: InviteRoomStatus.sending));

    final failures = <InviteFailure>[];
    for (final userId in userIds) {
      // Sem conexão os próximos falhariam igual; não vale esperar cada timeout.
      if (failures.lastOrNull?.type == RoomActionFailureType.network) {
        failures.add(InviteFailure(userId, RoomActionFailureType.network));
        continue;
      }
      final result = await _repository.inviteUser(_roomId, userId);
      if (isClosed) return;
      if (result case Error(:final error)) {
        log('Convidar $userId falhou', name: 'rooms', error: error);
        failures.add(
          InviteFailure(
            userId,
            error is RoomActionFailure
                ? error.type
                : RoomActionFailureType.unknown,
          ),
        );
      }
    }
    emit(
      failures.isEmpty
          ? const InviteRoomState(status: InviteRoomStatus.sent)
          : InviteRoomState(
              status: InviteRoomStatus.failure,
              failures: failures,
            ),
    );
  }
}
