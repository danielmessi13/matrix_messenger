import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_action_failure.dart';
import 'package:matrix_messenger/features/rooms/ui/invite_room/view_models/invite_room_state.dart';
import 'package:matrix_messenger/features/rooms/ui/invite_room/view_models/invite_room_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

class _PerUserRoomRepository extends FakeRoomRepository {
  final results = <String, Result<void>>{};

  @override
  Future<Result<void>> inviteUser(String roomId, String userId) async {
    await super.inviteUser(roomId, userId);
    return results[userId] ?? const Result.ok(null);
  }
}

void main() {
  late _PerUserRoomRepository repository;
  late InviteRoomViewModel viewModel;

  setUp(() {
    repository = _PerUserRoomRepository();
    viewModel = InviteRoomViewModel(repository, '!sala:b.c');
  });

  tearDown(() async {
    await viewModel.close();
    await repository.dispose();
  });

  test('convida um por um e termina em sent quando todos dão certo', () async {
    await viewModel.send(['@ana:b.c', '@bia:b.c']);

    expect(repository.invitedUsers, [
      ('!sala:b.c', '@ana:b.c'),
      ('!sala:b.c', '@bia:b.c'),
    ]);
    expect(
      viewModel.state,
      const InviteRoomState(status: InviteRoomStatus.sent),
    );
  });

  test('falha parcial guarda id e motivo de cada falha', () async {
    repository.results['@ana:b.c'] = const Result.error(
      RoomActionFailure(RoomActionFailureType.forbidden),
    );
    repository.results['@cid:b.c'] = const Result.error(
      FormatException('?'),
    );

    await viewModel.send(['@ana:b.c', '@bia:b.c', '@cid:b.c']);

    expect(repository.invitedUsers, hasLength(3));
    expect(
      viewModel.state,
      const InviteRoomState(
        status: InviteRoomStatus.failure,
        failures: [
          InviteFailure('@ana:b.c', RoomActionFailureType.forbidden),
          InviteFailure('@cid:b.c', RoomActionFailureType.unknown),
        ],
      ),
    );
  });

  test('depois de uma falha de rede marca os restantes sem chamar', () async {
    repository.results['@bia:b.c'] = const Result.error(
      RoomActionFailure(RoomActionFailureType.network),
    );

    await viewModel.send(['@ana:b.c', '@bia:b.c', '@cid:b.c', '@dan:b.c']);

    expect(repository.invitedUsers, [
      ('!sala:b.c', '@ana:b.c'),
      ('!sala:b.c', '@bia:b.c'),
    ]);
    expect(
      viewModel.state,
      const InviteRoomState(
        status: InviteRoomStatus.failure,
        failures: [
          InviteFailure('@bia:b.c', RoomActionFailureType.network),
          InviteFailure('@cid:b.c', RoomActionFailureType.network),
          InviteFailure('@dan:b.c', RoomActionFailureType.network),
        ],
      ),
    );
  });

  test('ignora outro envio enquanto envia', () async {
    repository.inviteUserGate = Completer<void>();

    final first = viewModel.send(['@ana:b.c']);
    expect(viewModel.state.status, InviteRoomStatus.sending);
    await viewModel.send(['@bia:b.c']);

    repository.inviteUserGate!.complete();
    await first;

    expect(repository.invitedUsers, [('!sala:b.c', '@ana:b.c')]);
    expect(viewModel.state.status, InviteRoomStatus.sent);
  });

  test('novo envio depois da falha limpa as falhas anteriores', () async {
    repository.results['@ana:b.c'] = const Result.error(
      RoomActionFailure(RoomActionFailureType.network),
    );
    await viewModel.send(['@ana:b.c']);
    expect(viewModel.state.failures, hasLength(1));

    repository.results.clear();
    await viewModel.send(['@ana:b.c']);

    expect(
      viewModel.state,
      const InviteRoomState(status: InviteRoomStatus.sent),
    );
  });
}
