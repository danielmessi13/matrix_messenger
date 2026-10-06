import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/ui/invite_room/view_models/can_invite_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;

  setUp(() => repository = FakeRoomRepository());

  tearDown(() => repository.dispose());

  const room = Room(id: '!sala:b.c', name: 'sala');

  test('começa sem permissão e reflete o repositório', () async {
    repository.canInviteValue = true;
    final viewModel = CanInviteViewModel(repository, '!sala:b.c');
    expect(viewModel.state, isFalse);

    await viewModel.load();

    expect(viewModel.state, isTrue);
    expect(repository.canInviteCalls, ['!sala:b.c']);
    await viewModel.close();
  });

  test('recarrega quando a sala é atualizada no sync', () async {
    final viewModel = CanInviteViewModel(
      repository,
      '!sala:b.c',
      debounce: Duration.zero,
    );
    await viewModel.load();
    expect(viewModel.state, isFalse);

    repository.canInviteValue = true;
    repository.roomsController.add([room]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(viewModel.state, isTrue);
    expect(repository.canInviteCalls, ['!sala:b.c', '!sala:b.c']);
    await viewModel.close();
  });

  test('ignora emissões sem a sala', () async {
    final viewModel = CanInviteViewModel(
      repository,
      '!sala:b.c',
      debounce: Duration.zero,
    );
    await viewModel.load();

    repository.roomsController.add([const Room(id: '!outra:b.c', name: 'x')]);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(repository.canInviteCalls, ['!sala:b.c']);
    await viewModel.close();
  });

  test('rajada de emissões vira uma chamada só', () async {
    final viewModel = CanInviteViewModel(
      repository,
      '!sala:b.c',
      debounce: const Duration(milliseconds: 20),
    );
    repository.roomsController
      ..add([room])
      ..add([room])
      ..add([room]);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(repository.canInviteCalls, ['!sala:b.c']);
    await viewModel.close();
  });

  test('resultado antigo não sobrescreve o mais novo', () async {
    final viewModel = CanInviteViewModel(repository, '!sala:b.c');
    final gate = Completer<void>();
    repository.canInviteGate = gate;
    final first = viewModel.load();
    repository.canInviteGate = null;
    repository.canInviteValue = true;
    await viewModel.load();
    expect(viewModel.state, isTrue);

    repository.canInviteValue = false;
    gate.complete();
    await first;

    expect(viewModel.state, isTrue);
    await viewModel.close();
  });

  test('close cancela a assinatura das salas', () async {
    final viewModel = CanInviteViewModel(
      repository,
      '!sala:b.c',
      debounce: Duration.zero,
    );
    await viewModel.close();

    expect(repository.roomsController.hasListener, isFalse);
  });
}
