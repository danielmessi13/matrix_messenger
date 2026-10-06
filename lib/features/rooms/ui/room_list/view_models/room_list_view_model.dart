import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/room_repository.dart';
import '../../../domain/models/message_hit.dart';
import '../../../domain/models/message_search_failure.dart';
import '../../../domain/models/room.dart';
import '../../../domain/models/room_filter.dart';
import '../../../domain/models/sync_state.dart';
import 'message_search_state.dart';
import 'room_list_state.dart';

const kMessageSearchDebounce = Duration(milliseconds: 300);

class RoomListViewModel extends Cubit<RoomListState> {
  RoomListViewModel(
    this._repository, {
    this._debounce = kMessageSearchDebounce,
  }) : super(const RoomListState());

  final RoomRepository _repository;

  final Duration _debounce;

  Timer? _searchTimer;

  int _searchSeq = 0;

  int _focusSeq = 0;

  StreamSubscription<List<Room>>? _rooms;

  StreamSubscription<SyncState>? _syncState;

  void init() {
    _rooms ??= _repository.rooms.listen(_onRooms);
    _syncState ??= _repository.syncState.listen(
      (syncState) => emit(state.copyWith(syncState: syncState)),
    );
  }

  void selectFilter(RoomFilter filter) => emit(state.copyWith(filter: filter));

  void search(String query) {
    final changed = query.trim() != state.query.trim();
    emit(state.copyWith(query: query));
    if (changed) _searchMessages(_debounce);
  }

  void clearSearch() => search('');

  void retryMessageSearch() => _searchMessages(Duration.zero);

  Future<void> loadMoreMessages() async {
    final messages = state.messages;
    final nextBatch = messages.nextBatch;
    if (nextBatch == null || messages.loadingMore) return;
    final seq = _searchSeq;
    emit(state.copyWith(messages: _withLoadingMore(messages, true)));
    final result = await _repository.searchMessages(
      state.query.trim(),
      nextBatch: nextBatch,
    );
    if (isClosed || seq != _searchSeq) return;
    final current = state.messages;
    emit(
      state.copyWith(
        messages: switch (result) {
          Ok(:final value) => MessageSearch(
            status: MessageSearchStatus.ready,
            hits: List.unmodifiable([...current.hits, ...value.hits]),
            nextBatch: value.nextBatch,
          ),
          Error() => _withLoadingMore(current, false),
        },
      ),
    );
  }

  void selectRoom(String roomId) {
    if (state.rooms.any((room) => room.id == roomId)) {
      emit(
        state.copyWith(
          selectedRoomId: () => roomId,
          pendingRoomId: () => null,
          focus: () => null,
        ),
      );
    }
  }

  void openMessage(MessageHit hit) {
    if (!state.rooms.any((room) => room.id == hit.roomId)) return;
    emit(
      state.copyWith(
        selectedRoomId: () => hit.roomId,
        pendingRoomId: () => null,
        focus: () => EventFocus(hit.eventId, ++_focusSeq),
      ),
    );
  }

  void _searchMessages(Duration delay) {
    _searchTimer?.cancel();
    _searchSeq++;
    final term = state.query.trim();
    if (term.isEmpty) {
      emit(state.copyWith(messages: const MessageSearch()));
      return;
    }
    emit(
      state.copyWith(
        messages: const MessageSearch(status: MessageSearchStatus.loading),
      ),
    );
    final seq = _searchSeq;
    if (delay == Duration.zero) {
      _runMessageSearch(term, seq);
    } else {
      _searchTimer = Timer(delay, () => _runMessageSearch(term, seq));
    }
  }

  Future<void> _runMessageSearch(String term, int seq) async {
    final result = await _repository.searchMessages(term);
    if (isClosed || seq != _searchSeq) return;
    emit(
      state.copyWith(
        messages: switch (result) {
          Ok(:final value) => MessageSearch(
            status: MessageSearchStatus.ready,
            hits: value.hits,
            nextBatch: value.nextBatch,
          ),
          Error(:final error) => MessageSearch(
            status: MessageSearchStatus.failed,
            failure: error is MessageSearchFailure
                ? error.type
                : MessageSearchFailureType.unknown,
          ),
        },
      ),
    );
  }

  MessageSearch _withLoadingMore(MessageSearch messages, bool loadingMore) =>
      MessageSearch(
        status: messages.status,
        hits: messages.hits,
        nextBatch: messages.nextBatch,
        loadingMore: loadingMore,
      );

  // A sala recém-criada só entra na lista na próxima volta do sync.
  void selectWhenAvailable(String roomId) {
    if (state.rooms.any((room) => room.id == roomId)) {
      selectRoom(roomId);
    } else {
      emit(state.copyWith(pendingRoomId: () => roomId));
    }
  }

  void _onRooms(List<Room> rooms) {
    final pending = state.pendingRoomId;
    final arrived = pending != null && rooms.any((room) => room.id == pending);
    final selected = arrived ? pending : state.selectedRoomId;
    final keepSelection = rooms.any((room) => room.id == selected);
    final next = keepSelection ? selected : null;
    emit(
      state.copyWith(
        rooms: rooms,
        loaded: true,
        selectedRoomId: () => next,
        pendingRoomId: arrived ? () => null : null,
        focus: next != state.selectedRoomId ? () => null : null,
      ),
    );
  }

  @override
  Future<void> close() async {
    _searchTimer?.cancel();
    await _rooms?.cancel();
    await _syncState?.cancel();
    return super.close();
  }
}
