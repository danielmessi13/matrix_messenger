import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/data/repositories/room_repository_matrix.dart';
import 'package:matrix_messenger/features/rooms/domain/models/create_room_failure.dart';
import 'package:matrix_messenger/features/rooms/domain/models/join_room_failure.dart';
import 'package:matrix_messenger/features/rooms/domain/models/message_hit.dart';
import 'package:matrix_messenger/features/rooms/domain/models/message_search_failure.dart';
import 'package:matrix_messenger/features/rooms/domain/models/new_room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/sync_state.dart';
import 'package:matrix_messenger/features/rooms/domain/models/user_check.dart';
import 'package:matrix_messenger/src/rust/api/rooms.dart' as bridge;
import 'package:matrix_messenger/src/rust/api/search.dart' as search;

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

  test('criar sala converte o pedido e o resultado', () async {
    service.createRoomResult = const Result.ok(
      bridge.CreatedRoom(roomId: '!x:b.c', failedInvites: ['@joao:b.c']),
    );

    final result = await repository.createRoom(
      const NewRoom(
        name: 'Plantão',
        topic: 'Coordenação',
        isPublic: true,
        invites: ['@ana:b.c', '@joao:b.c'],
      ),
    );

    expect(
      (result as Ok<CreatedRoom>).value,
      const CreatedRoom(roomId: '!x:b.c', failedInvites: ['@joao:b.c']),
    );
    expect(service.createdRooms.single.name, 'Plantão');
    expect(service.createdRooms.single.topic, 'Coordenação');
    expect(service.createdRooms.single.isPublic, isTrue);
    expect(service.createdRooms.single.invites, ['@ana:b.c', '@joao:b.c']);
  });

  test('falha ao criar vira CreateRoomFailure com o tipo', () async {
    for (final (kind, type) in [
      (bridge.CreateRoomErrorKind.network, CreateRoomFailureType.network),
      (bridge.CreateRoomErrorKind.unknown, CreateRoomFailureType.unknown),
    ]) {
      service.createRoomResult = Result.error(
        bridge.CreateRoomError(kind: kind, message: 'x'),
      );

      final result = await repository.createRoom(
        const NewRoom(name: 'a', isPublic: false),
      );

      expect(((result as Error).error as CreateRoomFailure).type, type);
    }
  });

  test('erro que não veio do Rust ao criar é unknown', () async {
    service.createRoomResult = Result.error(Exception('sem sessão'));

    final result = await repository.createRoom(
      const NewRoom(name: 'a', isPublic: false),
    );

    expect(
      ((result as Error).error as CreateRoomFailure).type,
      CreateRoomFailureType.unknown,
    );
  });

  test('verificação de usuário converte cada status', () async {
    final cases = <(bridge.UserCheck, UserCheck)>[
      (
        const bridge.UserCheck(
          status: bridge.UserCheckStatus.found,
          displayName: 'Ana',
        ),
        const UserFound('Ana'),
      ),
      (
        const bridge.UserCheck(
          status: bridge.UserCheckStatus.notFound,
          displayName: null,
        ),
        const UserNotFound(),
      ),
      (
        const bridge.UserCheck(
          status: bridge.UserCheckStatus.unknown,
          displayName: null,
        ),
        const UserUnknown(),
      ),
    ];
    for (final (input, expected) in cases) {
      service.checkUserResult = Result.ok(input);
      expect(await repository.checkUser('@ana:b.c'), expected);
    }
  });

  test('erro na verificação vira UserUnknown', () async {
    service.checkUserResult = Result.error(Exception('sem sessão'));

    expect(await repository.checkUser('@ana:b.c'), const UserUnknown());
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

  test('busca de mensagens converte a página e repassa o next_batch', () async {
    service.searchMessagesResult = const Result.ok(
      search.MessageSearchPage(
        hits: [
          search.MessageHit(
            roomId: '!a:b.c',
            roomName: 'Geral',
            isDirect: true,
            eventId: r'$e',
            senderName: 'Bob',
            isOwn: false,
            body: 'deploy',
            timestampMs: 1000,
          ),
        ],
        nextBatch: 'b3',
      ),
    );

    final result = await repository.searchMessages('deploy', nextBatch: 'b2');

    expect(
      (result as Ok<MessageSearchPage>).value,
      MessageSearchPage(
        hits: [
          MessageHit(
            roomId: '!a:b.c',
            roomName: 'Geral',
            isDirect: true,
            eventId: r'$e',
            senderName: 'Bob',
            body: 'deploy',
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        ],
        nextBatch: 'b3',
      ),
    );
    expect(service.searches, [('deploy', 'b2')]);
  });

  test('falha na busca vira MessageSearchFailure com o tipo', () async {
    for (final (error, type) in [
      (
        const search.SearchError(
          kind: search.SearchErrorKind.network,
          message: 'x',
        ),
        MessageSearchFailureType.network,
      ),
      (
        const search.SearchError(
          kind: search.SearchErrorKind.unknown,
          message: 'x',
        ),
        MessageSearchFailureType.unknown,
      ),
      (Exception('sem sessão'), MessageSearchFailureType.unknown),
    ]) {
      service.searchMessagesResult = Result.error(error);

      final result = await repository.searchMessages('deploy');

      expect(((result as Error).error as MessageSearchFailure).type, type);
    }
  });
}
