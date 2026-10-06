import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/domain/models/create_room_failure.dart';
import 'package:matrix_messenger/features/rooms/domain/models/new_room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/user_check.dart';
import 'package:matrix_messenger/features/rooms/ui/invite_chips/view_models/invite_chips_state.dart';
import 'package:matrix_messenger/features/rooms/ui/new_room/view_models/new_room_state.dart';
import 'package:matrix_messenger/features/rooms/ui/new_room/view_models/new_room_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;
  late NewRoomViewModel viewModel;

  setUp(() {
    repository = FakeRoomRepository();
    viewModel = NewRoomViewModel(repository);
  });

  tearDown(() async {
    await viewModel.close();
    await repository.dispose();
  });

  List<(String, InviteChipStatus)> chips() => [
    for (final chip in viewModel.invites.state.chips) (chip.id, chip.status),
  ];

  test('estado inicial: privada, vazio, sem poder criar', () {
    expect(viewModel.state, const NewRoomState());
    expect(viewModel.state.isPublic, isFalse);
    expect(viewModel.state.shareHistory, isTrue);
    expect(viewModel.canSubmit, isFalse);
  });

  test(
    'criar sala privada envia a escolha de compartilhar o histórico',
    () async {
      viewModel
        ..nameChanged('Plantão')
        ..shareHistoryChanged(false);
      expect(viewModel.state.shareHistory, isFalse);

      await viewModel.submit();

      expect(repository.createdRooms, [
        const NewRoom(name: 'Plantão', isPublic: false, shareHistory: false),
      ]);
    },
  );

  test('nome só com espaços não libera o Criar', () {
    viewModel.nameChanged('   ');
    expect(viewModel.canSubmit, isFalse);

    viewModel.nameChanged(' Plantão ');
    expect(viewModel.canSubmit, isTrue);
  });

  test('formato inválido não consulta o servidor e bloqueia o Criar', () async {
    viewModel.nameChanged('Plantão');
    viewModel.invites.queryChanged('joao@prosa');
    await viewModel.invites.addInvite();

    expect(chips(), [('joao@prosa', InviteChipStatus.invalidFormat)]);
    expect(viewModel.invites.state.invalidFormatIds, ['joao@prosa']);
    expect(viewModel.canSubmit, isFalse);
    expect(repository.checkedUsers, isEmpty);
  });

  test(
    'usuário inexistente fica vermelho e bloqueia; desconhecido libera',
    () async {
      repository.userChecks['@joao:b.co'] = const UserNotFound();
      repository.userChecks['@rui:b.co'] = const UserUnknown();
      viewModel.nameChanged('Plantão');

      viewModel.invites.queryChanged('@joao:b.co');
      await viewModel.invites.addInvite();
      viewModel.invites.queryChanged('@rui:b.co');
      await viewModel.invites.addInvite();

      expect(chips(), [
        ('@joao:b.co', InviteChipStatus.notFound),
        ('@rui:b.co', InviteChipStatus.unknown),
      ]);
      expect(viewModel.invites.state.notFoundIds, ['@joao:b.co']);
      expect(viewModel.canSubmit, isFalse);

      viewModel.invites.removeInvite(0);
      expect(viewModel.canSubmit, isTrue);
    },
  );

  test('chip em verificação bloqueia o Criar', () async {
    repository.checkUserGate = Completer<void>();
    viewModel.nameChanged('Plantão');
    viewModel.invites.queryChanged('@ana:b.co');

    final adding = viewModel.invites.addInvite();
    expect(chips(), [('@ana:b.co', InviteChipStatus.checking)]);
    expect(viewModel.canSubmit, isFalse);

    repository.checkUserGate!.complete();
    await adding;
    expect(viewModel.canSubmit, isTrue);
  });

  test('criar envia nome e tópico aparados, visibilidade e convites', () async {
    viewModel
      ..nameChanged('  Plantão ')
      ..topicChanged('  ')
      ..visibilityChanged(true);
    viewModel.invites.queryChanged('@ana:b.co,');
    await pumpEventQueue();

    await viewModel.submit();

    expect(repository.createdRooms, [
      const NewRoom(name: 'Plantão', isPublic: true, invites: ['@ana:b.co']),
    ]);
    expect(viewModel.state.status, NewRoomStatus.success);
    expect(viewModel.state.created, const CreatedRoom(roomId: '!nova:b.c'));
  });

  test('texto pendente no convite vira chip e cria no mesmo envio', () async {
    viewModel
      ..nameChanged('Plantão')
      ..topicChanged('Coordenação');
    viewModel.invites.queryChanged('@ana:b.co');

    await viewModel.submit();

    expect(repository.createdRooms.single.invites, ['@ana:b.co']);
    expect(repository.createdRooms.single.topic, 'Coordenação');
    expect(viewModel.state.status, NewRoomStatus.success);
  });

  test('texto pendente de usuário inexistente não cria', () async {
    repository.userChecks['@joao:b.co'] = const UserNotFound();
    viewModel.nameChanged('Plantão');
    viewModel.invites.queryChanged('@joao:b.co');

    await viewModel.submit();

    expect(repository.createdRooms, isEmpty);
    expect(chips(), [('@joao:b.co', InviteChipStatus.notFound)]);
    expect(viewModel.state.status, NewRoomStatus.idle);
  });

  test(
    'texto colado pendente espera todas as verificações antes de criar',
    () async {
      repository
        ..userChecks['@joao:b.co'] = const UserNotFound()
        ..checkUserGate = Completer<void>();
      viewModel.nameChanged('Plantão');
      viewModel.invites.queryChanged('@ana:b.co @joao:b.co');

      final submitting = viewModel.submit();
      await pumpEventQueue();
      expect(chips(), [
        ('@ana:b.co', InviteChipStatus.checking),
        ('@joao:b.co', InviteChipStatus.checking),
      ]);
      repository.checkUserGate!.complete();
      await submitting;

      expect(repository.createdRooms, isEmpty);
      expect(chips(), [
        ('@ana:b.co', InviteChipStatus.found),
        ('@joao:b.co', InviteChipStatus.notFound),
      ]);
    },
  );

  test('texto colado pendente válido cria com todos os convites', () async {
    viewModel.nameChanged('Plantão');
    viewModel.invites.queryChanged('@ana:b.co,@bia:b.co');

    await viewModel.submit();

    expect(repository.createdRooms.single.invites, ['@ana:b.co', '@bia:b.co']);
  });

  test('sem nome não cria', () async {
    await viewModel.submit();

    expect(repository.createdRooms, isEmpty);
  });

  test('criando: ignora outro envio', () async {
    repository.createRoomGate = Completer<void>();
    viewModel.nameChanged('Plantão');

    final first = viewModel.submit();
    expect(viewModel.state.status, NewRoomStatus.creating);
    expect(viewModel.state.creating, isTrue);
    expect(viewModel.canSubmit, isFalse);
    await viewModel.submit();
    repository.createRoomGate!.complete();
    await first;

    expect(repository.createdRooms, hasLength(1));
  });

  test('falha guarda o tipo e permite tentar de novo', () async {
    repository.createRoomResult = const Result.error(
      CreateRoomFailure(CreateRoomFailureType.network),
    );
    viewModel.nameChanged('Plantão');

    await viewModel.submit();
    expect(viewModel.state.status, NewRoomStatus.failure);
    expect(viewModel.state.failure, CreateRoomFailureType.network);
    expect(viewModel.state.name, 'Plantão');
    expect(viewModel.canSubmit, isTrue);

    repository.createRoomResult = const Result.ok(
      CreatedRoom(roomId: '!x:b.c'),
    );
    await viewModel.submit();
    expect(viewModel.state.status, NewRoomStatus.success);
    expect(viewModel.state.failure, isNull);
  });

  test('erro que não é CreateRoomFailure vira unknown', () async {
    repository.createRoomResult = Result.error(Exception('x'));
    viewModel.nameChanged('Plantão');

    await viewModel.submit();

    expect(viewModel.state.failure, CreateRoomFailureType.unknown);
  });

  test('fechar também fecha os convites', () async {
    await viewModel.close();

    expect(viewModel.invites.isClosed, isTrue);
  });

  test('aba começa em criar e troca para entrar', () {
    expect(viewModel.state.tab, NewRoomTab.create);

    viewModel.tabChanged(NewRoomTab.join);

    expect(viewModel.state.tab, NewRoomTab.join);
  });
}
