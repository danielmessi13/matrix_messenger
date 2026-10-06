import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/domain/models/join_room_failure.dart';
import 'package:matrix_messenger/features/rooms/ui/new_room/view_models/join_room_state.dart';
import 'package:matrix_messenger/features/rooms/ui/new_room/view_models/join_room_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;
  late JoinRoomViewModel viewModel;

  setUp(() {
    repository = FakeRoomRepository();
    viewModel = JoinRoomViewModel(repository);
  });

  tearDown(() async {
    await viewModel.close();
    await repository.dispose();
  });

  test('estado inicial vazio e sem poder entrar', () {
    expect(viewModel.state, const JoinRoomState());
    expect(viewModel.state.canSubmit, isFalse);
  });

  test('alvo só com espaços não libera Entrar', () {
    viewModel.targetChanged('   ');
    expect(viewModel.state.canSubmit, isFalse);

    viewModel.targetChanged(' #sala:b.c ');
    expect(viewModel.state.canSubmit, isTrue);
  });

  test('entrar manda o alvo aparado e guarda o id da sala', () async {
    viewModel.targetChanged('  https://matrix.to/#/!a:b.c?via=b.c \n');

    await viewModel.submit();

    expect(repository.joinedTargets, ['https://matrix.to/#/!a:b.c?via=b.c']);
    expect(viewModel.state.status, JoinRoomStatus.success);
    expect(viewModel.state.roomId, '!entrou:b.c');
    expect(viewModel.state.canSubmit, isFalse);
  });

  test('sem alvo não chama o repositório', () async {
    await viewModel.submit();

    expect(repository.joinedTargets, isEmpty);
  });

  test('entrando: ignora outro envio', () async {
    repository.joinRoomGate = Completer<void>();
    viewModel.targetChanged('#sala:b.c');

    final first = viewModel.submit();
    expect(viewModel.state.joining, isTrue);
    expect(viewModel.state.canSubmit, isFalse);
    await viewModel.submit();
    repository.joinRoomGate!.complete();
    await first;

    expect(repository.joinedTargets, hasLength(1));
  });

  test('depois do sucesso, outro envio é ignorado', () async {
    viewModel.targetChanged('#sala:b.c');
    await viewModel.submit();

    await viewModel.submit();

    expect(repository.joinedTargets, hasLength(1));
  });

  test('cada falha guarda o tipo e permite tentar de novo', () async {
    viewModel.targetChanged('#sala:b.c');
    for (final type in JoinRoomFailureType.values) {
      repository.joinRoomResult = Result.error(JoinRoomFailure(type));

      await viewModel.submit();

      expect(viewModel.state.status, JoinRoomStatus.failure);
      expect(viewModel.state.failure, type);
      expect(viewModel.state.target, '#sala:b.c');
      expect(viewModel.state.canSubmit, isTrue);
    }

    repository.joinRoomResult = const Result.ok('!x:b.c');
    await viewModel.submit();
    expect(viewModel.state.status, JoinRoomStatus.success);
    expect(viewModel.state.failure, isNull);
  });

  test('erro que não é JoinRoomFailure vira unknown', () async {
    repository.joinRoomResult = Result.error(Exception('x'));
    viewModel.targetChanged('#sala:b.c');

    await viewModel.submit();

    expect(viewModel.state.failure, JoinRoomFailureType.unknown);
  });
}
