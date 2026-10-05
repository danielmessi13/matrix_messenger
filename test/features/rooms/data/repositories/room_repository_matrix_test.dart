import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository_matrix.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/sync_state.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart' as bridge;

import '../../../../../testing/fakes/services/fake_matrix_service.dart';

void main() {
  late FakeMatrixService service;
  late RoomRepositoryMatrix repository;

  setUp(() {
    service = FakeMatrixService();
    repository = RoomRepositoryMatrix(service);
  });

  tearDown(() => service.dispose());

  test('converte RoomSummary em Room', () async {
    final received = repository.rooms.first;
    service.roomsController.add([
      const bridge.RoomSummary(
        id: '!a:b.c',
        name: 'Sala A',
        isDirect: true,
        isInvite: false,
        unreadMessages: 3,
        unreadMentions: 1,
        memberCount: 2,
        heroes: ['Bob'],
        latest: bridge.LatestMessage(
          senderName: 'Bob',
          isOwn: false,
          kind: bridge.LatestMessageKind.encrypted,
          body: null,
          timestampMs: 1000,
        ),
      ),
    ]);

    expect(await received, [
      Room(
        id: '!a:b.c',
        name: 'Sala A',
        isDirect: true,
        unreadMessages: 3,
        unreadMentions: 1,
        memberCount: 2,
        heroes: const ['Bob'],
        latest: LatestMessage(
          senderName: 'Bob',
          isOwn: false,
          kind: LatestMessageKind.encrypted,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      ),
    ]);
  });

  test('converte cada SyncStatus', () async {
    final received = repository.syncState.take(5).toList();
    for (final status in bridge.SyncStatus.values) {
      service.syncStatusController.add(status);
    }

    expect(await received, [
      SyncState.connecting,
      SyncState.running,
      SyncState.offline,
      SyncState.unsupported,
      SyncState.error,
    ]);
  });
}
