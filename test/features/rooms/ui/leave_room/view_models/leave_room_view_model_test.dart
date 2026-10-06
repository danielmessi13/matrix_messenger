import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_action_failure.dart';
import 'package:matrix_messenger/features/rooms/ui/leave_room/view_models/leave_room_state.dart';
import 'package:matrix_messenger/features/rooms/ui/leave_room/view_models/leave_room_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;

  setUp(() => repository = FakeRoomRepository());

  tearDown(() => repository.dispose());

  LeaveRoomViewModel build() => LeaveRoomViewModel(repository, '!sala:b.c');

  test('estado inicial é idle', () async {
    final viewModel = build();
    expect(viewModel.state, const LeaveRoomState());
    await viewModel.close();
  });

  blocTest<LeaveRoomViewModel, LeaveRoomState>(
    'sair com sucesso passa por leaving e termina em left',
    build: build,
    act: (viewModel) => viewModel.leave(),
    expect: () => const [
      LeaveRoomState(status: LeaveRoomStatus.leaving),
      LeaveRoomState(status: LeaveRoomStatus.left),
    ],
    verify: (_) => expect(repository.leftRooms, ['!sala:b.c']),
  );

  blocTest<LeaveRoomViewModel, LeaveRoomState>(
    'falha emite failure com o tipo e permite tentar de novo',
    build: () {
      repository.leaveRoomResult = const Result.error(
        RoomActionFailure(RoomActionFailureType.network),
      );
      return build();
    },
    act: (viewModel) async {
      await viewModel.leave();
      await viewModel.leave();
    },
    expect: () => const [
      LeaveRoomState(status: LeaveRoomStatus.leaving),
      LeaveRoomState(
        status: LeaveRoomStatus.failure,
        failure: RoomActionFailureType.network,
      ),
      LeaveRoomState(status: LeaveRoomStatus.leaving),
      LeaveRoomState(
        status: LeaveRoomStatus.failure,
        failure: RoomActionFailureType.network,
      ),
    ],
  );

  blocTest<LeaveRoomViewModel, LeaveRoomState>(
    'erro fora do domínio vira unknown',
    build: () {
      repository.leaveRoomResult = Result.error(Exception('x'));
      return build();
    },
    act: (viewModel) => viewModel.leave(),
    expect: () => const [
      LeaveRoomState(status: LeaveRoomStatus.leaving),
      LeaveRoomState(
        status: LeaveRoomStatus.failure,
        failure: RoomActionFailureType.unknown,
      ),
    ],
  );

  blocTest<LeaveRoomViewModel, LeaveRoomState>(
    'ignora outro pedido enquanto o primeiro está em andamento',
    build: () {
      repository.leaveRoomGate = Completer<void>();
      return build();
    },
    act: (viewModel) async {
      final first = viewModel.leave();
      await viewModel.leave();
      repository.leaveRoomGate!.complete();
      await first;
    },
    expect: () => const [
      LeaveRoomState(status: LeaveRoomStatus.leaving),
      LeaveRoomState(status: LeaveRoomStatus.left),
    ],
    verify: (_) => expect(repository.leftRooms, ['!sala:b.c']),
  );
}
