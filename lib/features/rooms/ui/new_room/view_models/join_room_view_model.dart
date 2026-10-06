import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/join_room_failure.dart';
import 'join_room_state.dart';

class JoinRoomViewModel extends Cubit<JoinRoomState> {
  JoinRoomViewModel(this._repository) : super(const JoinRoomState());

  final RoomRepository _repository;

  void targetChanged(String target) => emit(state.copyWith(target: target));

  Future<void> submit() async {
    if (isClosed || !state.canSubmit) return;
    emit(state.copyWith(status: JoinRoomStatus.joining, failure: () => null));

    final result = await _repository.joinRoom(state.target.trim());
    if (isClosed) return;
    switch (result) {
      case Ok(:final value):
        emit(
          state.copyWith(status: JoinRoomStatus.success, roomId: () => value),
        );
      case Error(:final error):
        log('Entrar na sala falhou', name: 'rooms', error: error);
        emit(
          state.copyWith(
            status: JoinRoomStatus.failure,
            failure: () => error is JoinRoomFailure
                ? error.type
                : JoinRoomFailureType.unknown,
          ),
        );
    }
  }
}
