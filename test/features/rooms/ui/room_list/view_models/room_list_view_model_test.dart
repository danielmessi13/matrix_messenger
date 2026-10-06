import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/domain/models/message_hit.dart';
import 'package:matrix_messenger/features/rooms/domain/models/message_search_failure.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_filter.dart';
import 'package:matrix_messenger/features/rooms/domain/models/sync_state.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/view_models/message_search_state.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/view_models/room_list_state.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/view_models/room_list_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';
import '../../../../../../testing/models/room.dart';

void main() {
  late FakeRoomRepository repository;

  setUp(() => repository = FakeRoomRepository());
  tearDown(() => repository.dispose());

  test('estado inicial ainda não carregou', () {
    final state = RoomListViewModel(repository).state;
    expect(state.loaded, isFalse);
    expect(state.syncState, SyncState.connecting);
    expect(state.selectedRoom, isNull);
  });

  blocTest<RoomListViewModel, RoomListState>(
    'primeira lista marca como carregado',
    build: () => RoomListViewModel(repository)..init(),
    act: (_) => repository.roomsController.add(kRooms),
    expect: () => [RoomListState(rooms: kRooms, loaded: true)],
  );

  blocTest<RoomListViewModel, RoomListState>(
    'repassa o estado do sync',
    build: () => RoomListViewModel(repository)..init(),
    act: (_) => repository.syncStateController.add(SyncState.offline),
    expect: () => const [RoomListState(syncState: SyncState.offline)],
  );

  test('não lidas por filtro somam o contador de cada filtro', () {
    final state = RoomListState(
      rooms: [
        ...kRooms,
        const Room(id: '!t:b.c', name: 'obras', unreadThreadReplies: 3),
      ],
      loaded: true,
    );
    expect(state.unreadByFilter, {
      RoomFilter.inbox: 6,
      RoomFilter.mentions: 1,
      RoomFilter.threads: 3,
      RoomFilter.rooms: 4,
      RoomFilter.direct: 2,
    });
    expect(state.visibleUnread, 6);
    expect(state.copyWith(filter: RoomFilter.threads).visibleUnread, 3);
  });

  blocTest<RoomListViewModel, RoomListState>(
    'selecionar Threads muda o filtro',
    build: () => RoomListViewModel(repository),
    act: (viewModel) => viewModel.selectFilter(RoomFilter.threads),
    expect: () => const [RoomListState(filter: RoomFilter.threads)],
  );

  blocTest<RoomListViewModel, RoomListState>(
    'buscar e limpar a busca',
    build: () => RoomListViewModel(repository),
    act: (viewModel) => viewModel
      ..search('ana')
      ..clearSearch(),
    expect: () => const [
      RoomListState(query: 'ana'),
      RoomListState(
        query: 'ana',
        messages: MessageSearch(status: MessageSearchStatus.loading),
      ),
      RoomListState(
        messages: MessageSearch(status: MessageSearchStatus.loading),
      ),
      RoomListState(),
    ],
  );

  blocTest<RoomListViewModel, RoomListState>(
    'seleciona uma sala que existe e ignora uma que não existe',
    build: () => RoomListViewModel(repository),
    seed: () => RoomListState(rooms: kRooms, loaded: true),
    act: (viewModel) => viewModel
      ..selectRoom('!nao-existe:b.c')
      ..selectRoom(kDirectRoom.id),
    expect: () => [
      RoomListState(
        rooms: kRooms,
        loaded: true,
        selectedRoomId: kDirectRoom.id,
      ),
    ],
    verify: (viewModel) => expect(viewModel.state.selectedRoom, kDirectRoom),
  );

  blocTest<RoomListViewModel, RoomListState>(
    'sala selecionada que some da lista limpa a seleção',
    build: () => RoomListViewModel(repository)..init(),
    seed: () => RoomListState(
      rooms: kRooms,
      loaded: true,
      selectedRoomId: kDirectRoom.id,
    ),
    act: (_) => repository.roomsController.add([kTeamRoom]),
    expect: () => [
      RoomListState(rooms: [kTeamRoom], loaded: true),
    ],
  );

  blocTest<RoomListViewModel, RoomListState>(
    'sala selecionada que continua na lista mantém a seleção',
    build: () => RoomListViewModel(repository)..init(),
    seed: () => RoomListState(
      rooms: kRooms,
      loaded: true,
      selectedRoomId: kTeamRoom.id,
    ),
    act: (_) => repository.roomsController.add([kTeamRoom]),
    expect: () => [
      RoomListState(
        rooms: [kTeamRoom],
        loaded: true,
        selectedRoomId: kTeamRoom.id,
      ),
    ],
  );

  test('fechar cancela as inscrições', () async {
    final viewModel = RoomListViewModel(repository)..init();
    await viewModel.close();
    expect(repository.roomsController.hasListener, isFalse);
    expect(repository.syncStateController.hasListener, isFalse);
  });

  test(
    'selecionar quando disponível: sala já na lista seleciona na hora',
    () async {
      final viewModel = RoomListViewModel(repository)..init();
      addTearDown(viewModel.close);
      repository.roomsController.add(kRooms);
      await pumpEventQueue();

      viewModel.selectWhenAvailable(kTeamRoom.id);

      expect(viewModel.state.selectedRoomId, kTeamRoom.id);
      expect(viewModel.state.pendingRoomId, isNull);
    },
  );

  test('selecionar quando disponível: sala nova seleciona ao chegar', () async {
    final viewModel = RoomListViewModel(repository)..init();
    addTearDown(viewModel.close);
    repository.roomsController.add(kRooms);
    await pumpEventQueue();

    viewModel.selectWhenAvailable('!nova:b.c');
    expect(viewModel.state.selectedRoomId, isNull);
    expect(viewModel.state.pendingRoomId, '!nova:b.c');

    repository.roomsController.add(kRooms);
    await pumpEventQueue();
    expect(viewModel.state.pendingRoomId, '!nova:b.c');

    const created = Room(id: '!nova:b.c', name: 'Plantão');
    repository.roomsController.add([...kRooms, created]);
    await pumpEventQueue();
    expect(viewModel.state.selectedRoomId, '!nova:b.c');
    expect(viewModel.state.selectedRoom, created);
    expect(viewModel.state.pendingRoomId, isNull);
  });

  test('sala nova escondida pelo filtro abre mesmo assim', () async {
    final viewModel = RoomListViewModel(repository)..init();
    addTearDown(viewModel.close);
    viewModel
      ..selectFilter(RoomFilter.direct)
      ..selectWhenAvailable('!nova:b.c');

    const created = Room(id: '!nova:b.c', name: 'Plantão');
    repository.roomsController.add([...kRooms, created]);
    await pumpEventQueue();

    expect(viewModel.state.visibleRooms, isNot(contains(created)));
    expect(viewModel.state.selectedRoom, created);
  });

  test('selecionar outra sala descarta a pendente', () async {
    final viewModel = RoomListViewModel(repository)..init();
    addTearDown(viewModel.close);
    repository.roomsController.add(kRooms);
    await pumpEventQueue();

    viewModel
      ..selectWhenAvailable('!nova:b.c')
      ..selectRoom(kTeamRoom.id);
    repository.roomsController.add([
      ...kRooms,
      const Room(id: '!nova:b.c', name: 'Plantão'),
    ]);
    await pumpEventQueue();

    expect(viewModel.state.selectedRoomId, kTeamRoom.id);
    expect(viewModel.state.pendingRoomId, isNull);
  });

  group('busca de mensagens', () {
    MessageHit hit(
      String eventId, {
      String roomId = '!lancamento:matrix.org',
    }) => MessageHit(
      roomId: roomId,
      roomName: 'lançamento-q4',
      eventId: eventId,
      senderName: 'Diego',
      body: 'deploy',
      timestamp: DateTime(2026, 10, 4),
    );

    blocTest<RoomListViewModel, RoomListState>(
      'digitando rápido faz uma busca só, com o último termo',
      setUp: () => repository.searchResult = Result.ok(
        MessageSearchPage(hits: [hit(r'$a')], nextBatch: 'b2'),
      ),
      build: () => RoomListViewModel(repository),
      act: (viewModel) => viewModel
        ..search('de')
        ..search('dep')
        ..search('deploy '),
      wait: kMessageSearchDebounce + const Duration(milliseconds: 50),
      skip: 4,
      expect: () => [
        RoomListState(
          query: 'deploy ',
          messages: MessageSearch(
            status: MessageSearchStatus.ready,
            hits: [hit(r'$a')],
            nextBatch: 'b2',
          ),
        ),
      ],
      verify: (_) => expect(repository.searches, [('deploy', null)]),
    );

    blocTest<RoomListViewModel, RoomListState>(
      'mudar só espaços no fim não busca de novo',
      build: () => RoomListViewModel(repository, debounce: Duration.zero),
      act: (viewModel) async {
        viewModel.search('deploy');
        await pumpEventQueue();
        viewModel.search('deploy  ');
        await pumpEventQueue();
      },
      verify: (viewModel) {
        expect(repository.searches, [('deploy', null)]);
        expect(viewModel.state.messages.status, MessageSearchStatus.ready);
      },
    );

    blocTest<RoomListViewModel, RoomListState>(
      'erro vira falha com o tipo e tentar de novo busca outra vez',
      setUp: () => repository.searchResult = const Result.error(
        MessageSearchFailure(MessageSearchFailureType.network),
      ),
      build: () => RoomListViewModel(repository),
      seed: () => const RoomListState(
        query: 'deploy',
      ),
      act: (viewModel) async {
        viewModel.retryMessageSearch();
        await pumpEventQueue();
        repository.searchResult = const Result.ok(MessageSearchPage(hits: []));
        viewModel.retryMessageSearch();
        await pumpEventQueue();
      },
      expect: () => const [
        RoomListState(
          query: 'deploy',
          messages: MessageSearch(status: MessageSearchStatus.loading),
        ),
        RoomListState(
          query: 'deploy',
          messages: MessageSearch(
            status: MessageSearchStatus.failed,
            failure: MessageSearchFailureType.network,
          ),
        ),
        RoomListState(
          query: 'deploy',
          messages: MessageSearch(status: MessageSearchStatus.loading),
        ),
        RoomListState(
          query: 'deploy',
          messages: MessageSearch(status: MessageSearchStatus.ready),
        ),
      ],
    );

    blocTest<RoomListViewModel, RoomListState>(
      'mais resultados acrescenta a próxima página pelo next_batch',
      setUp: () => repository.searchResult = Result.ok(
        MessageSearchPage(hits: [hit(r'$b')]),
      ),
      build: () => RoomListViewModel(repository),
      seed: () => RoomListState(
        query: 'deploy',
        messages: MessageSearch(
          status: MessageSearchStatus.ready,
          hits: [hit(r'$a')],
          nextBatch: 'b2',
        ),
      ),
      act: (viewModel) => viewModel.loadMoreMessages(),
      expect: () => [
        RoomListState(
          query: 'deploy',
          messages: MessageSearch(
            status: MessageSearchStatus.ready,
            hits: [hit(r'$a')],
            nextBatch: 'b2',
            loadingMore: true,
          ),
        ),
        RoomListState(
          query: 'deploy',
          messages: MessageSearch(
            status: MessageSearchStatus.ready,
            hits: [hit(r'$a'), hit(r'$b')],
          ),
        ),
      ],
      verify: (_) => expect(repository.searches, [('deploy', 'b2')]),
    );

    test('resposta de uma busca já substituída é descartada', () async {
      final gate = repository.searchGate = Completer<void>();
      repository.searchResult = Result.ok(
        MessageSearchPage(hits: [hit(r'$velho')]),
      );
      final viewModel = RoomListViewModel(repository, debounce: Duration.zero)
        ..search('velho');
      addTearDown(viewModel.close);
      await pumpEventQueue();
      expect(repository.searches, [('velho', null)]);

      viewModel.clearSearch();
      gate.complete();
      await pumpEventQueue();

      expect(viewModel.state.messages, const MessageSearch());
    });

    blocTest<RoomListViewModel, RoomListState>(
      'abrir resultado seleciona a sala e pede o foco; tocar na sala limpa',
      build: () => RoomListViewModel(repository),
      seed: () => RoomListState(rooms: kRooms, loaded: true),
      act: (viewModel) => viewModel
        ..openMessage(hit(r'$fora', roomId: '!sumiu:b.c'))
        ..openMessage(hit(r'$a', roomId: kTeamRoom.id))
        ..openMessage(hit(r'$a', roomId: kTeamRoom.id))
        ..selectRoom(kTeamRoom.id),
      expect: () => [
        RoomListState(
          rooms: kRooms,
          loaded: true,
          selectedRoomId: kTeamRoom.id,
          focus: const EventFocus(r'$a', 1),
        ),
        RoomListState(
          rooms: kRooms,
          loaded: true,
          selectedRoomId: kTeamRoom.id,
          focus: const EventFocus(r'$a', 2),
        ),
        RoomListState(
          rooms: kRooms,
          loaded: true,
          selectedRoomId: kTeamRoom.id,
        ),
      ],
    );

    test('sala nova que chega depois descarta o foco da busca', () async {
      final viewModel = RoomListViewModel(repository)..init();
      addTearDown(viewModel.close);
      repository.roomsController.add(kRooms);
      await pumpEventQueue();
      viewModel
        ..openMessage(hit(r'$a', roomId: kTeamRoom.id))
        ..selectWhenAvailable('!nova:b.c');
      expect(viewModel.state.focus, isNotNull);

      repository.roomsController.add([
        ...kRooms,
        const Room(id: '!nova:b.c', name: 'Plantão'),
      ]);
      await pumpEventQueue();

      expect(viewModel.state.selectedRoomId, '!nova:b.c');
      expect(viewModel.state.focus, isNull);
    });
  });
}
