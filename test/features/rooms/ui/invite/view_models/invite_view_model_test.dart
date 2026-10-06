import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/ui/invite/view_models/invite_state.dart';
import 'package:matrix_messenger/features/rooms/ui/invite/view_models/invite_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;

  setUp(() => repository = FakeRoomRepository());

  tearDown(() => repository.dispose());

  InviteViewModel build() => InviteViewModel(repository, '!convite:b.c');

  test('estado inicial é idle', () {
    expect(build().state, const InviteState());
  });

  blocTest<InviteViewModel, InviteState>(
    'aceitar com sucesso fica em accepting até a sala mudar',
    build: build,
    act: (viewModel) => viewModel.accept(),
    expect: () => const [InviteState(status: InviteStatus.accepting)],
    verify: (_) => expect(repository.accepted, ['!convite:b.c']),
  );

  blocTest<InviteViewModel, InviteState>(
    'recusar com sucesso fica em declining até a sala sumir',
    build: build,
    act: (viewModel) => viewModel.decline(),
    expect: () => const [InviteState(status: InviteStatus.declining)],
    verify: (_) => expect(repository.declined, ['!convite:b.c']),
  );

  blocTest<InviteViewModel, InviteState>(
    'falha emite failure e permite tentar de novo',
    build: () {
      repository.inviteResult = Result.error(Exception('rede'));
      return build();
    },
    act: (viewModel) async {
      await viewModel.accept();
      await viewModel.decline();
    },
    expect: () => const [
      InviteState(status: InviteStatus.accepting),
      InviteState(status: InviteStatus.failure),
      InviteState(status: InviteStatus.declining),
      InviteState(status: InviteStatus.failure),
    ],
  );

  blocTest<InviteViewModel, InviteState>(
    'ignora outra resposta enquanto a primeira está em andamento',
    build: () {
      repository.inviteGate = Completer<void>();
      return build();
    },
    act: (viewModel) async {
      final first = viewModel.accept();
      await viewModel.decline();
      await viewModel.accept();
      repository.inviteGate!.complete();
      await first;
    },
    expect: () => const [InviteState(status: InviteStatus.accepting)],
    verify: (_) {
      expect(repository.accepted, hasLength(1));
      expect(repository.declined, isEmpty);
    },
  );

  test('não emite depois de fechado', () async {
    repository.inviteGate = Completer<void>();
    repository.inviteResult = Result.error(Exception('rede'));
    final viewModel = build();

    final pending = viewModel.accept();
    await viewModel.close();
    repository.inviteGate!.complete();

    await expectLater(pending, completes);
  });
}
