import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_filter.dart';
import 'package:matrix_messenger/features/rooms/domain/models/sync_state.dart';
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

  test('filtro e busca combinados, sem diferenciar acento nem maiúscula', () {
    final state = RoomListState(
      rooms: kRooms,
      loaded: true,
      filter: RoomFilter.rooms,
      query: 'LANCAMENTO',
    );
    expect(state.visibleRooms, [kTeamRoom]);
    expect(state.searching, isTrue);
  });

  test('busca sem resultado deixa a lista visível vazia', () {
    final state = RoomListState(rooms: kRooms, loaded: true, query: 'xyz');
    expect(state.visibleRooms, isEmpty);
  });

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
    expect: () => const [RoomListState(query: 'ana'), RoomListState()],
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
}
