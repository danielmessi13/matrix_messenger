import '../../../../core/services/matrix_service.dart';
import '../../../../core/utils/result.dart';
import '../../../../src/rust/api/rooms.dart' as bridge;
import '../../../../src/rust/api/search.dart' as search;
import '../../domain/models/create_room_failure.dart';
import '../../domain/models/join_room_failure.dart';
import '../../domain/models/message_hit.dart';
import '../../domain/models/message_search_failure.dart';
import '../../domain/models/new_room.dart';
import '../../domain/models/room.dart';
import '../../domain/models/sync_state.dart';
import '../../domain/models/user_check.dart';
import 'latest_message_mapper.dart';
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
  Future<Result<CreatedRoom>> createRoom(NewRoom room) async {
    final request = bridge.NewRoom(
      name: room.name,
      topic: room.topic,
      isPublic: room.isPublic,
      invites: room.invites,
    );
    switch (await _service.createRoom(request)) {
      case Ok(:final value):
        return Result.ok(
          CreatedRoom(
            roomId: value.roomId,
            failedInvites: List.unmodifiable(value.failedInvites),
          ),
        );
      case Error(:final error):
        return Result.error(_toCreateFailure(error));
    }
  }

  @override
  Future<UserCheck> checkUser(String userId) async =>
      switch (await _service.checkUser(userId)) {
        Ok(:final value) => switch (value.status) {
          bridge.UserCheckStatus.found => UserFound(value.displayName),
          bridge.UserCheckStatus.notFound => const UserNotFound(),
          bridge.UserCheckStatus.unknown => const UserUnknown(),
        },
        Error() => const UserUnknown(),
      };

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

  @override
  Future<Result<MessageSearchPage>> searchMessages(
    String term, {
    String? nextBatch,
  }) async {
    switch (await _service.searchMessages(term, nextBatch: nextBatch)) {
      case Ok(:final value):
        return Result.ok(
          MessageSearchPage(
            hits: List.unmodifiable(value.hits.map(_toHit)),
            nextBatch: value.nextBatch,
          ),
        );
      case Error(:final error):
        return Result.error(_toSearchFailure(error));
    }
  }

  MessageHit _toHit(search.MessageHit hit) => MessageHit(
    roomId: hit.roomId,
    roomName: hit.roomName,
    isDirect: hit.isDirect,
    eventId: hit.eventId,
    senderName: hit.senderName,
    isOwn: hit.isOwn,
    body: hit.body,
    timestamp: DateTime.fromMillisecondsSinceEpoch(hit.timestampMs),
  );

  MessageSearchFailure _toSearchFailure(Exception error) => switch (error) {
    search.SearchError(:final kind, :final message) => MessageSearchFailure(
      switch (kind) {
        search.SearchErrorKind.network => MessageSearchFailureType.network,
        search.SearchErrorKind.unknown => MessageSearchFailureType.unknown,
      },
      message,
    ),
    _ => MessageSearchFailure(MessageSearchFailureType.unknown, '$error'),
  };

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

  CreateRoomFailure _toCreateFailure(Exception error) => switch (error) {
    bridge.CreateRoomError(:final kind, :final message) => CreateRoomFailure(
      switch (kind) {
        bridge.CreateRoomErrorKind.network => CreateRoomFailureType.network,
        bridge.CreateRoomErrorKind.unknown => CreateRoomFailureType.unknown,
      },
      message,
    ),
    _ => CreateRoomFailure(CreateRoomFailureType.unknown, '$error'),
  };

  Room _toRoom(bridge.RoomSummary summary) => Room(
    id: summary.id,
    name: summary.name,
    isDirect: summary.isDirect,
    isInvite: summary.isInvite,
    isPublic: summary.isPublic,
    unreadMessages: summary.unreadMessages,
    unreadMentions: summary.unreadMentions,
    memberCount: summary.memberCount,
    heroes: List.unmodifiable(summary.heroes),
    latest: switch (summary.latest) {
      null => null,
      final latest => toLatestMessage(latest),
    },
  );

  SyncState _toSyncState(bridge.SyncStatus status) => switch (status) {
    bridge.SyncStatus.connecting => SyncState.connecting,
    bridge.SyncStatus.running => SyncState.running,
    bridge.SyncStatus.offline => SyncState.offline,
    bridge.SyncStatus.unsupported => SyncState.unsupported,
    bridge.SyncStatus.error => SyncState.error,
  };
}
