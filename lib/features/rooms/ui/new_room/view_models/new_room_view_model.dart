import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/create_room_failure.dart';
import '../../../domain/models/new_room.dart';
import '../../../domain/models/user_check.dart';
import 'new_room_state.dart';

final _userIdPattern = RegExp(
  r'^@[a-z0-9._=\-/]+:[a-z0-9.\-]+\.[a-z]{2,}(:\d+)?$',
  caseSensitive: false,
);

final _endsWithSeparator = RegExp(r'[,\s]$');

final _separators = RegExp(r'[,\s]+');

class NewRoomViewModel extends Cubit<NewRoomState> {
  NewRoomViewModel(this._repository) : super(const NewRoomState());

  final RoomRepository _repository;

  void nameChanged(String name) => emit(state.copyWith(name: name));

  void topicChanged(String topic) => emit(state.copyWith(topic: topic));

  void visibilityChanged(bool isPublic) =>
      emit(state.copyWith(isPublic: isPublic));

  void tabChanged(NewRoomTab tab) => emit(state.copyWith(tab: tab));

  void queryChanged(String query) {
    if (_endsWithSeparator.hasMatch(query)) {
      unawaited(_addChips(query));
    } else {
      emit(state.copyWith(query: query));
    }
  }

  Future<void> addInvite() => _addChips(state.query);

  void removeInvite(int index) =>
      emit(state.copyWith(invites: [...state.invites]..removeAt(index)));

  void removeLastInvite() {
    if (state.invites.isEmpty) return;
    removeInvite(state.invites.length - 1);
  }

  Future<void> submit() async {
    if (isClosed || state.creating) return;
    if (state.query.trim().isNotEmpty) await addInvite();
    if (isClosed || !state.canSubmit) return;
    emit(state.copyWith(status: NewRoomStatus.creating, failure: () => null));

    final topic = state.topic.trim();
    final result = await _repository.createRoom(
      NewRoom(
        name: state.name.trim(),
        topic: topic.isEmpty ? null : topic,
        isPublic: state.isPublic,
        invites: [for (final chip in state.invites) chip.id],
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

  // Colar "@a:x.org, @b:y.org" vira um chip por ID.
  Future<void> _addChips(String raw) async {
    emit(state.copyWith(query: ''));
    await Future.wait([
      for (final id in raw.split(_separators))
        if (id.isNotEmpty) _addChip(id),
    ]);
  }

  Future<void> _addChip(String id) async {
    final lower = id.toLowerCase();
    if (state.invites.any((c) => c.id.toLowerCase() == lower)) return;
    final valid = _userIdPattern.hasMatch(id);
    final status = valid
        ? InviteChipStatus.checking
        : InviteChipStatus.invalidFormat;
    emit(state.copyWith(invites: [...state.invites, InviteChip(id, status)]));
    if (!valid) return;

    final check = await _repository.checkUser(id);
    if (isClosed) return;
    final resolved = switch (check) {
      UserFound(:final displayName) => InviteChip(
        id,
        InviteChipStatus.found,
        displayName,
      ),
      UserNotFound() => InviteChip(id, InviteChipStatus.notFound),
      UserUnknown() => InviteChip(id, InviteChipStatus.unknown),
    };
    // O chip pode ter sido removido enquanto a verificação rodava.
    emit(
      state.copyWith(
        invites: [
          for (final chip in state.invites)
            chip.id == id && chip.status == InviteChipStatus.checking
                ? resolved
                : chip,
        ],
      ),
    );
  }
}
