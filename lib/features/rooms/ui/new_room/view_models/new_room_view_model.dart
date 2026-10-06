import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/create_room_failure.dart';
import '../../../domain/models/new_room.dart';
import '../../invite_chips/view_models/invite_chips_view_model.dart';
import 'new_room_state.dart';

class NewRoomViewModel extends Cubit<NewRoomState> {
  NewRoomViewModel(this._repository)
    : invites = InviteChipsViewModel(_repository),
      super(const NewRoomState());

  final RoomRepository _repository;

  final InviteChipsViewModel invites;

  bool get canSubmit => state.canSubmitWith(invites.state);

  void nameChanged(String name) => emit(state.copyWith(name: name));

  void topicChanged(String topic) => emit(state.copyWith(topic: topic));

  void visibilityChanged(bool isPublic) =>
      emit(state.copyWith(isPublic: isPublic));

  void shareHistoryChanged(bool shareHistory) =>
      emit(state.copyWith(shareHistory: shareHistory));

  void tabChanged(NewRoomTab tab) => emit(state.copyWith(tab: tab));

  Future<void> submit() async {
    if (isClosed || state.creating) return;
    // Sem texto pendente não há await: o segundo envio já vê o creating.
    if (invites.state.hasPendingQuery) await invites.flush();
    if (isClosed || !canSubmit) return;
    emit(state.copyWith(status: NewRoomStatus.creating, failure: () => null));

    final topic = state.topic.trim();
    final result = await _repository.createRoom(
      NewRoom(
        name: state.name.trim(),
        topic: topic.isEmpty ? null : topic,
        isPublic: state.isPublic,
        invites: invites.state.ids,
        shareHistory: state.shareHistory,
      ),
    );
    if (isClosed) return;
    switch (result) {
      case Ok(:final value):
        emit(
          state.copyWith(status: NewRoomStatus.success, created: () => value),
        );
      case Error(:final error):
        log('Criar sala falhou', name: 'rooms', error: error);
        emit(
          state.copyWith(
            status: NewRoomStatus.failure,
            failure: () => error is CreateRoomFailure
                ? error.type
                : CreateRoomFailureType.unknown,
          ),
        );
    }
  }

  @override
  Future<void> close() async {
    await invites.close();
    return super.close();
  }
}
