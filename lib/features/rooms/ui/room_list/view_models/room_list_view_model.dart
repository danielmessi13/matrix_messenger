import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/room.dart';
import '../../../domain/models/room_filter.dart';
import '../../../domain/models/sync_state.dart';
import 'room_list_state.dart';

class RoomListViewModel extends Cubit<RoomListState> {
  RoomListViewModel(this._repository) : super(const RoomListState());

  final RoomRepository _repository;

  StreamSubscription<List<Room>>? _rooms;

  StreamSubscription<SyncState>? _syncState;

  void init() {
    _rooms ??= _repository.rooms.listen(_onRooms);
    _syncState ??= _repository.syncState.listen(
      (syncState) => emit(state.copyWith(syncState: syncState)),
    );
  }

  void selectFilter(RoomFilter filter) {
    if (filter.enabled) emit(state.copyWith(filter: filter));
  }

  void search(String query) => emit(state.copyWith(query: query));

  void clearSearch() => emit(state.copyWith(query: ''));

  void selectRoom(String roomId) {
    if (state.rooms.any((room) => room.id == roomId)) {
      emit(state.copyWith(selectedRoomId: () => roomId));
    }
  }

  void _onRooms(List<Room> rooms) {
    final selected = state.selectedRoomId;
    final keepSelection = rooms.any((room) => room.id == selected);
    emit(
      state.copyWith(
        rooms: rooms,
        loaded: true,
        selectedRoomId: () => keepSelection ? selected : null,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _rooms?.cancel();
    await _syncState?.cancel();
    return super.close();
  }
}
