import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/room_repository.dart';
import 'invite_state.dart';

class InviteViewModel extends Cubit<InviteState> {
  InviteViewModel(this._repository, this._roomId) : super(const InviteState());

  final RoomRepository _repository;

  final String _roomId;

  Future<void> accept() =>
      _respond(InviteStatus.accepting, _repository.acceptInvite);

  Future<void> decline() =>
      _respond(InviteStatus.declining, _repository.declineInvite);

  Future<void> _respond(
    InviteStatus running,
    Future<Result<void>> Function(String roomId) action,
  ) async {
    if (isClosed || state.isRunning) return;
    emit(InviteState(status: running));

    // No sucesso o sync muda a sala e o painel troca sozinho; o indicador fica até lá.
    if (await action(_roomId) case Error(:final error)) {
      log('Resposta ao convite falhou', name: 'rooms', error: error);
      if (!isClosed) emit(const InviteState(status: InviteStatus.failure));
    }
  }
}
