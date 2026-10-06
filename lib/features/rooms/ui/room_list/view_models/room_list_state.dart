import 'package:equatable/equatable.dart';

import '../../../../../core/utils/string_extensions.dart';
import '../../../domain/models/room.dart';
import '../../../domain/models/room_filter.dart';
import '../../../domain/models/sync_state.dart';

final class RoomListState extends Equatable {
  const RoomListState({
    this.rooms = const [],
    this.loaded = false,
    this.syncState = SyncState.connecting,
    this.filter = RoomFilter.inbox,
    this.query = '',
    this.selectedRoomId,
  });

  final List<Room> rooms;

  final bool loaded;

  final SyncState syncState;

  final RoomFilter filter;

  final String query;

  final String? selectedRoomId;

  bool get searching => query.trim().isNotEmpty;

  List<Room> get visibleRooms {
    final folded = query.trim().foldedForSearch;
    return [
      for (final room in rooms)
        if (filter.matches(room) &&
            (folded.isEmpty || room.name.foldedForSearch.contains(folded)))
          room,
    ];
  }

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
    String? Function()? selectedRoomId,
  }) => RoomListState(
    rooms: rooms ?? this.rooms,
    loaded: loaded ?? this.loaded,
    syncState: syncState ?? this.syncState,
    filter: filter ?? this.filter,
    query: query ?? this.query,
    selectedRoomId: selectedRoomId == null
        ? this.selectedRoomId
        : selectedRoomId(),
  );

  @override
  List<Object?> get props => [
    rooms,
    loaded,
    syncState,
    filter,
    query,
    selectedRoomId,
  ];
}
