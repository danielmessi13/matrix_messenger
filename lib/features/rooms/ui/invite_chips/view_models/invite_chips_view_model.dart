import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/user_check.dart';
import 'invite_chips_state.dart';

// Server name da spec: hostname (sem exigir TLD, vale localhost), IPv4 ou [IPv6], porta opcional.
final _userIdPattern = RegExp(
  r'^@[a-z0-9._=\-/+]+:(\[[0-9a-f:.]+\]|[a-z0-9.\-]+)(:\d{1,5})?$',
  caseSensitive: false,
);

final _endsWithSeparator = RegExp(r'[,\s]$');

final _separators = RegExp(r'[,\s]+');

class InviteChipsViewModel extends Cubit<InviteChipsState> {
  InviteChipsViewModel(this._repository, {Set<String> exclude = const {}})
    : _exclude = {for (final id in exclude) id.toLowerCase()},
      super(const InviteChipsState());

  final RoomRepository _repository;

  final Set<String> _exclude;

  void queryChanged(String query) {
    if (_endsWithSeparator.hasMatch(query)) {
      unawaited(_addChips(query));
    } else {
      emit(state.copyWith(query: query));
    }
  }

  Future<void> addInvite() => _addChips(state.query);

  // Para o envio: o texto ainda no campo vira chip e as verificações terminam.
  Future<void> flush() async {
    if (state.hasPendingQuery) await addInvite();
  }

  void removeInvite(int index) =>
      emit(state.copyWith(chips: [...state.chips]..removeAt(index)));

  // Backspace no campo vazio: o último chip volta para o texto, para corrigir.
  void editLastInvite() {
    if (state.chips.isEmpty) return;
    final last = state.chips.last;
    emit(
      state.copyWith(
        chips: [...state.chips]..removeLast(),
        query: last.id,
      ),
    );
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
    if (_exclude.contains(lower) ||
        state.chips.any((c) => c.id.toLowerCase() == lower)) {
      return;
    }
    final valid = _userIdPattern.hasMatch(id);
    final status = valid
        ? InviteChipStatus.checking
        : InviteChipStatus.invalidFormat;
    emit(state.copyWith(chips: [...state.chips, InviteChip(id, status)]));
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
        chips: [
          for (final chip in state.chips)
            chip.id == id && chip.status == InviteChipStatus.checking
                ? resolved
                : chip,
        ],
      ),
    );
  }
}
