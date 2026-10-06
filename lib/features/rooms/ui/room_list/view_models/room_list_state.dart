import 'package:equatable/equatable.dart';

import '../../../domain/models/room.dart';
import '../../../domain/models/room_filter.dart';
import '../../../domain/models/sync_state.dart';
import 'message_search_state.dart';

final class RoomListState extends Equatable {
  const RoomListState({
    this.rooms = const [],
    this.loaded = false,
    this.syncState = SyncState.connecting,
    this.filter = RoomFilter.inbox,
    this.query = '',
    this.messages = const MessageSearch(),
    this.selectedRoomId,
    this.pendingRoomId,
    this.focus,
  });

  final List<Room> rooms;

  final bool loaded;

  final SyncState syncState;

  final RoomFilter filter;

  final String query;

  final MessageSearch messages;

  final String? selectedRoomId;

  final String? pendingRoomId;

  final EventFocus? focus;

  bool get searching => query.trim().isNotEmpty;

  List<Room> get visibleRooms => rooms.where(filter.matches).toList();

  int get visibleUnread =>
      visibleRooms.fold(0, (sum, room) => sum + filter.unreadOf(room));

  Map<RoomFilter, int> get unreadByFilter => {
    for (final filter in RoomFilter.values)
      filter: rooms
          .where(filter.matches)
          .fold(0, (sum, room) => sum + filter.unreadOf(room)),
  };

  Room? get selectedRoom =>
      rooms.where((room) => room.id == selectedRoomId).firstOrNull;

  RoomListState copyWith({
    List<Room>? rooms,
    bool? loaded,
    SyncState? syncState,
    RoomFilter? filter,
    String? query,
    MessageSearch? messages,
    String? Function()? selectedRoomId,
    String? Function()? pendingRoomId,
    EventFocus? Function()? focus,
  }) => RoomListState(
    rooms: rooms ?? this.rooms,
    loaded: loaded ?? this.loaded,
    syncState: syncState ?? this.syncState,
    filter: filter ?? this.filter,
    query: query ?? this.query,
    messages: messages ?? this.messages,
    selectedRoomId: selectedRoomId == null
        ? this.selectedRoomId
        : selectedRoomId(),
    pendingRoomId: pendingRoomId == null ? this.pendingRoomId : pendingRoomId(),
    focus: focus == null ? this.focus : focus(),
  );

  @override
  List<Object?> get props => [
    rooms,
    loaded,
    syncState,
    filter,
    query,
    messages,
    selectedRoomId,
    pendingRoomId,
    focus,
  ];
}
