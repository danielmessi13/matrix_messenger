import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/room.dart';

class CanInviteViewModel extends Cubit<bool> {
  CanInviteViewModel(
    this._repository,
    this._roomId, {
    this._debounce = const Duration(milliseconds: 500),
  }) : super(false) {
    // Power level não entra no resumo da sala: recarrega a cada atualização dela.
    _rooms = _repository.rooms.listen(_onRooms);
  }

  final RoomRepository _repository;

  final String _roomId;

  final Duration _debounce;

  late final StreamSubscription<List<Room>> _rooms;

  Timer? _reload;

  var _seq = 0;

  Future<void> load() async {
    final seq = ++_seq;
    final allowed = await _repository.canInvite(_roomId);
    if (!isClosed && seq == _seq) emit(allowed);
  }

  void _onRooms(List<Room> rooms) {
    if (!rooms.any((room) => room.id == _roomId)) return;
    _reload?.cancel();
    _reload = Timer(_debounce, load);
  }

  @override
  Future<void> close() async {
    _reload?.cancel();
    await _rooms.cancel();
    return super.close();
  }
}
