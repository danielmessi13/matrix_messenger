import '../../../../core/services/matrix_service.dart';
import '../../../../core/utils/result.dart';
import '../../../../src/rust/api/rooms.dart' as bridge;
import '../../domain/models/join_room_failure.dart';
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

  @override
  Future<String?> roomLink(String roomId) async =>
      switch (await _service.roomLink(roomId)) {
        Ok(:final value) => value,
        Error() => null,
      };

  @override
  Future<Result<String>> joinRoom(String target) async {
    switch (await _service.joinRoom(target)) {
      case Ok(:final value):
        return Result.ok(value);
      case Error(:final error):
        return Result.error(_toJoinFailure(error));
    }
  }

  JoinRoomFailure _toJoinFailure(Exception error) => switch (error) {
    bridge.JoinRoomError(:final kind, :final message) => JoinRoomFailure(
      switch (kind) {
        bridge.JoinRoomErrorKind.invalidLink => JoinRoomFailureType.invalidLink,
        bridge.JoinRoomErrorKind.notFound => JoinRoomFailureType.notFound,
        bridge.JoinRoomErrorKind.forbidden => JoinRoomFailureType.forbidden,
        bridge.JoinRoomErrorKind.network => JoinRoomFailureType.network,
        bridge.JoinRoomErrorKind.unknown => JoinRoomFailureType.unknown,
      },
      message,
    ),
    _ => JoinRoomFailure(JoinRoomFailureType.unknown, '$error'),
  };

  Room _toRoom(bridge.RoomSummary summary) => Room(
    id: summary.id,
    name: summary.name,
    isDirect: summary.isDirect,
    isInvite: summary.isInvite,
    isPublic: summary.isPublic,
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
