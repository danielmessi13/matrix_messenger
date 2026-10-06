import '../../../../core/services/matrix_service.dart';
import '../../../../core/utils/result.dart';
import '../../../../src/rust/api/rooms.dart' as bridge;
import '../../domain/models/room.dart';
import '../../domain/models/sync_state.dart';
import 'room_repository.dart';

class RoomRepositoryMatrix implements RoomRepository {
  RoomRepositoryMatrix(this._service);

  final MatrixService _service;

  @override
  Stream<List<Room>> get rooms => _service.watchRooms().map(
    (rooms) => rooms.map(_toRoom).toList(growable: false),
  );

  @override
  Stream<SyncState> get syncState =>
      _service.watchSyncStatus().map(_toSyncState);

  @override
  Future<Result<void>> acceptInvite(String roomId) =>
      _service.acceptInvite(roomId);

  @override
  Future<Result<void>> declineInvite(String roomId) =>
      _service.declineInvite(roomId);

  Room _toRoom(bridge.RoomSummary summary) => Room(
    id: summary.id,
    name: summary.name,
    isDirect: summary.isDirect,
    isInvite: summary.isInvite,
    unreadMessages: summary.unreadMessages,
    unreadMentions: summary.unreadMentions,
    unreadThreadReplies: summary.unreadThreadReplies,
    memberCount: summary.memberCount,
    heroes: List.unmodifiable(summary.heroes),
    latest: switch (summary.latest) {
      null => null,
      final latest => LatestMessage(
        senderName: latest.senderName,
        isOwn: latest.isOwn,
        kind: _toKind(latest.kind),
        body: latest.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(latest.timestampMs),
      ),
    },
  );

  // O switch quebra se o Rust ganhar um caso novo.
  LatestMessageKind _toKind(bridge.LatestMessageKind kind) => switch (kind) {
    bridge.LatestMessageKind.text => LatestMessageKind.text,
    bridge.LatestMessageKind.image => LatestMessageKind.image,
    bridge.LatestMessageKind.file => LatestMessageKind.file,
    bridge.LatestMessageKind.encrypted => LatestMessageKind.encrypted,
    bridge.LatestMessageKind.other => LatestMessageKind.other,
  };

  SyncState _toSyncState(bridge.SyncStatus status) => switch (status) {
    bridge.SyncStatus.connecting => SyncState.connecting,
    bridge.SyncStatus.running => SyncState.running,
    bridge.SyncStatus.offline => SyncState.offline,
    bridge.SyncStatus.unsupported => SyncState.unsupported,
    bridge.SyncStatus.error => SyncState.error,
  };
}
