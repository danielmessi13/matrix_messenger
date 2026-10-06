import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/room_action_failure.dart';
import 'leave_room_state.dart';

class LeaveRoomViewModel extends Cubit<LeaveRoomState> {
  LeaveRoomViewModel(this._repository, this._roomId)
    : super(const LeaveRoomState());

  final RoomRepository _repository;

  final String _roomId;

  Future<void> leave() async {
    if (isClosed || state.status == LeaveRoomStatus.leaving) return;
    emit(const LeaveRoomState(status: LeaveRoomStatus.leaving));

    final result = await _repository.leaveRoom(_roomId);
    if (isClosed) return;
    switch (result) {
      // A sala some da lista pelo sync; o left só serve para fechar o diálogo.
      case Ok():
        emit(const LeaveRoomState(status: LeaveRoomStatus.left));
      case Error(:final error):
        log('Sair da sala falhou', name: 'rooms', error: error);
        emit(
          LeaveRoomState(
            status: LeaveRoomStatus.failure,
            failure: error is RoomActionFailure
                ? error.type
                : RoomActionFailureType.unknown,
          ),
        );
    }
  }
}
