import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/rooms/domain/models/create_room_failure.dart';
import 'package:matrix_messenger/features/rooms/domain/models/new_room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/user_check.dart';
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
    for (final chip in viewModel.state.invites) (chip.id, chip.status),
  ];

  test('estado inicial: privada, vazio, sem poder criar', () {
    expect(viewModel.state, const NewRoomState());
    expect(viewModel.state.isPublic, isFalse);
    expect(viewModel.state.canSubmit, isFalse);
  });

  test('nome só com espaços não libera o Criar', () {
    viewModel.nameChanged('   ');
    expect(viewModel.state.canSubmit, isFalse);

    viewModel.nameChanged(' Plantão ');
    expect(viewModel.state.canSubmit, isTrue);
  });

  test('Enter transforma o texto em chip verificado', () async {
    repository.userChecks['@ana:b.co'] = const UserFound('Ana');
    viewModel.queryChanged('@ana:b.co');

    await viewModel.addInvite();

    expect(chips(), [('@ana:b.co', InviteChipStatus.found)]);
    expect(viewModel.state.invites.single.displayName, 'Ana');
    expect(viewModel.state.query, '');
    expect(repository.checkedUsers, ['@ana:b.co']);
  });

  test('vírgula e espaço no fim também viram chip', () async {
    viewModel.queryChanged('@ana:b.co,');
    viewModel.queryChanged('@bia:b.co ');
    await pumpEventQueue();

    expect(chips(), [
      ('@ana:b.co', InviteChipStatus.found),
      ('@bia:b.co', InviteChipStatus.found),
    ]);
    expect(viewModel.state.query, '');
  });

  test('colar vários IDs com vírgula e espaço cria um chip por ID', () async {
    viewModel.queryChanged('@ana:b.co, @bia:b.co');

    await viewModel.addInvite();

    expect(chips(), [
      ('@ana:b.co', InviteChipStatus.found),
      ('@bia:b.co', InviteChipStatus.found),
    ]);
    expect(repository.checkedUsers, ['@ana:b.co', '@bia:b.co']);
    expect(viewModel.state.query, '');
  });

  test('colar com um pedaço inválido marca só esse pedaço', () async {
    viewModel.queryChanged('@ana:b.co, joao@prosa ');
    await pumpEventQueue();

    expect(chips(), [
      ('@ana:b.co', InviteChipStatus.found),
      ('joao@prosa', InviteChipStatus.invalidFormat),
    ]);
    expect(repository.checkedUsers, ['@ana:b.co']);
  });

  test('texto sem separador no fim só atualiza o campo', () {
    viewModel.queryChanged('@ana:b');

    expect(viewModel.state.query, '@ana:b');
    expect(viewModel.state.invites, isEmpty);
  });

  test('separador sozinho só limpa o campo', () async {
    viewModel.queryChanged(' ');
    viewModel.queryChanged(',');
    await pumpEventQueue();

    expect(viewModel.state.invites, isEmpty);
    expect(viewModel.state.query, '');
  });

  test('ID repetido, sem diferenciar maiúsculas, é ignorado', () async {
    viewModel.queryChanged('@ana:b.co');
    await viewModel.addInvite();
    viewModel.queryChanged('@ANA:B.CO');
    await viewModel.addInvite();

    expect(chips(), [('@ana:b.co', InviteChipStatus.found)]);
    expect(viewModel.state.query, '');
    expect(repository.checkedUsers, ['@ana:b.co']);
  });

  test('formato inválido não consulta o servidor e bloqueia o Criar', () async {
    viewModel
      ..nameChanged('Plantão')
      ..queryChanged('joao@prosa');
    await viewModel.addInvite();

    expect(chips(), [('joao@prosa', InviteChipStatus.invalidFormat)]);
    expect(viewModel.state.invalidFormatIds, ['joao@prosa']);
    expect(viewModel.state.canSubmit, isFalse);
    expect(repository.checkedUsers, isEmpty);
  });

  test(
    'usuário inexistente fica vermelho e bloqueia; desconhecido libera',
    () async {
      repository.userChecks['@joao:b.co'] = const UserNotFound();
      repository.userChecks['@rui:b.co'] = const UserUnknown();
      viewModel.nameChanged('Plantão');

      viewModel.queryChanged('@joao:b.co');
      await viewModel.addInvite();
      viewModel.queryChanged('@rui:b.co');
      await viewModel.addInvite();

      expect(chips(), [
        ('@joao:b.co', InviteChipStatus.notFound),
        ('@rui:b.co', InviteChipStatus.unknown),
      ]);
      expect(viewModel.state.notFoundIds, ['@joao:b.co']);
      expect(viewModel.state.canSubmit, isFalse);

      viewModel.removeInvite(0);
      expect(viewModel.state.canSubmit, isTrue);
    },
  );

  test('chip em verificação bloqueia o Criar', () async {
    repository.checkUserGate = Completer<void>();
    viewModel
      ..nameChanged('Plantão')
      ..queryChanged('@ana:b.co');

    final adding = viewModel.addInvite();
    expect(chips(), [('@ana:b.co', InviteChipStatus.checking)]);
    expect(viewModel.state.canSubmit, isFalse);

    repository.checkUserGate!.complete();
    await adding;
    expect(viewModel.state.canSubmit, isTrue);
  });

  test('resultado de chip removido durante a verificação é ignorado', () async {
    repository.checkUserGate = Completer<void>();
    repository.userChecks['@ana:b.co'] = const UserNotFound();
    viewModel.queryChanged('@ana:b.co');
    final adding = viewModel.addInvite();
    viewModel.queryChanged('@bia:b.co');
    final addingOther = viewModel.addInvite();

    viewModel.removeInvite(0);
    repository.checkUserGate!.complete();
    await adding;
    await addingOther;

    expect(chips(), [('@bia:b.co', InviteChipStatus.found)]);
  });

  test('Backspace com o campo vazio remove o último chip', () async {
    viewModel.queryChanged('@ana:b.co,');
    viewModel.queryChanged('@bia:b.co,');
    await pumpEventQueue();

    viewModel.removeLastInvite();
    expect(chips(), [('@ana:b.co', InviteChipStatus.found)]);

    viewModel
      ..removeLastInvite()
      ..removeLastInvite();
    expect(viewModel.state.invites, isEmpty);
  });

  test('criar envia nome e tópico aparados, visibilidade e convites', () async {
    viewModel
      ..nameChanged('  Plantão ')
      ..topicChanged('  ')
      ..visibilityChanged(true)
      ..queryChanged('@ana:b.co,');
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
      ..topicChanged('Coordenação')
      ..queryChanged('@ana:b.co');

    await viewModel.submit();

    expect(repository.createdRooms.single.invites, ['@ana:b.co']);
    expect(repository.createdRooms.single.topic, 'Coordenação');
    expect(viewModel.state.status, NewRoomStatus.success);
  });

  test('texto pendente de usuário inexistente não cria', () async {
    repository.userChecks['@joao:b.co'] = const UserNotFound();
    viewModel
      ..nameChanged('Plantão')
      ..queryChanged('@joao:b.co');

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
      viewModel
        ..nameChanged('Plantão')
        ..queryChanged('@ana:b.co @joao:b.co');

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
    viewModel
      ..nameChanged('Plantão')
      ..queryChanged('@ana:b.co,@bia:b.co');

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
    expect(viewModel.state.canSubmit, isFalse);
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
    expect(viewModel.state.canSubmit, isTrue);

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

  test('aceita porta no servidor e rejeita servidor sem domínio', () async {
    viewModel.queryChanged('@ana:b.co:8448');
    await viewModel.addInvite();
    viewModel.queryChanged('@ana:localhost');
    await viewModel.addInvite();

    expect(chips(), [
      ('@ana:b.co:8448', InviteChipStatus.found),
      ('@ana:localhost', InviteChipStatus.invalidFormat),
    ]);
  });

  test('aba começa em criar e troca para entrar', () {
    expect(viewModel.state.tab, NewRoomTab.create);

    viewModel.tabChanged(NewRoomTab.join);

    expect(viewModel.state.tab, NewRoomTab.join);
  });
}
