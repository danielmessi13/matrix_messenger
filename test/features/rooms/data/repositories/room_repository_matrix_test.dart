import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository_matrix.dart';
import 'package:matrix_messenger/features/rooms/domain/models/join_room_failure.dart';
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
        isPublic: true,
        unreadMessages: 3,
        unreadMentions: 1,
        unreadThreadReplies: 5,
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
        isPublic: true,
        unreadMessages: 3,
        unreadMentions: 1,
        unreadThreadReplies: 5,
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

  test('aceitar e recusar convite repassam ao serviço', () async {
    expect(await repository.acceptInvite('!a:b.c'), isA<Ok<void>>());
    expect(await repository.declineInvite('!b:b.c'), isA<Ok<void>>());

    expect(service.accepted, ['!a:b.c']);
    expect(service.declined, ['!b:b.c']);
  });

  test('link da sala repassa o valor do serviço', () async {
    expect(
      await repository.roomLink('!a:b.c'),
      'https://matrix.to/#/!a:b.c?via=b.c',
    );

    service.roomLinkResult = const Result.ok(null);
    expect(await repository.roomLink('!a:b.c'), isNull);
  });

  test('erro ao gerar o link vira null', () async {
    service.roomLinkResult = Result.error(Exception('sem sessão'));

    expect(await repository.roomLink('!a:b.c'), isNull);
  });

  test('entrar devolve o id da sala e repassa o alvo', () async {
    final result = await repository.joinRoom('#sala:b.c');

    expect((result as Ok<String>).value, '!entrou:b.c');
    expect(service.joinedTargets, ['#sala:b.c']);
  });

  test('falha ao entrar vira JoinRoomFailure com o tipo', () async {
    for (final (kind, type) in [
      (bridge.JoinRoomErrorKind.invalidLink, JoinRoomFailureType.invalidLink),
      (bridge.JoinRoomErrorKind.notFound, JoinRoomFailureType.notFound),
      (bridge.JoinRoomErrorKind.forbidden, JoinRoomFailureType.forbidden),
      (bridge.JoinRoomErrorKind.network, JoinRoomFailureType.network),
      (bridge.JoinRoomErrorKind.unknown, JoinRoomFailureType.unknown),
    ]) {
      service.joinRoomResult = Result.error(
        bridge.JoinRoomError(kind: kind, message: 'x'),
      );

      final result = await repository.joinRoom('!a:b.c');

      expect(((result as Error).error as JoinRoomFailure).type, type);
    }
  });

  test('erro que não veio do Rust ao entrar é unknown', () async {
    service.joinRoomResult = Result.error(Exception('sem sessão'));

    final result = await repository.joinRoom('!a:b.c');

    expect(
      ((result as Error).error as JoinRoomFailure).type,
      JoinRoomFailureType.unknown,
    );
  });
}
