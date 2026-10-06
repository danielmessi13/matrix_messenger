import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/domain/models/user_check.dart';
import 'package:matrix_messenger/features/rooms/ui/invite_chips/view_models/invite_chips_state.dart';
import 'package:matrix_messenger/features/rooms/ui/invite_chips/view_models/invite_chips_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;
  late InviteChipsViewModel viewModel;

  setUp(() {
    repository = FakeRoomRepository();
    viewModel = InviteChipsViewModel(repository);
  });

  tearDown(() async {
    await viewModel.close();
    await repository.dispose();
  });

  List<(String, InviteChipStatus)> chips() => [
    for (final chip in viewModel.state.chips) (chip.id, chip.status),
  ];

  test('estado inicial: vazio e sem bloquear', () {
    expect(viewModel.state, const InviteChipsState());
    expect(viewModel.state.blocksSubmit, isFalse);
    expect(viewModel.state.hasError, isFalse);
    expect(viewModel.state.hasUnknown, isFalse);
    expect(viewModel.state.ids, isEmpty);
  });

  test('Enter transforma o texto em chip verificado', () async {
    repository.userChecks['@ana:b.co'] = const UserFound('Ana');
    viewModel.queryChanged('@ana:b.co');

    await viewModel.addInvite();

    expect(chips(), [('@ana:b.co', InviteChipStatus.found)]);
    expect(viewModel.state.chips.single.displayName, 'Ana');
    expect(viewModel.state.query, '');
    expect(viewModel.state.ids, ['@ana:b.co']);
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
    expect(viewModel.state.chips, isEmpty);
  });

  test('separador sozinho só limpa o campo', () async {
    viewModel.queryChanged(' ');
    viewModel.queryChanged(',');
    await pumpEventQueue();

    expect(viewModel.state.chips, isEmpty);
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

  test('ID excluído, sem diferenciar maiúsculas, é ignorado', () async {
    final excluding = InviteChipsViewModel(
      repository,
      exclude: const {'@eu:b.co'},
    );
    addTearDown(excluding.close);

    excluding.queryChanged('@EU:b.co, @ana:b.co');
    await excluding.addInvite();

    expect(excluding.state.ids, ['@ana:b.co']);
    expect(repository.checkedUsers, ['@ana:b.co']);
  });

  test('formato inválido não consulta o servidor e bloqueia', () async {
    viewModel.queryChanged('joao@prosa');
    await viewModel.addInvite();

    expect(chips(), [('joao@prosa', InviteChipStatus.invalidFormat)]);
    expect(viewModel.state.invalidFormatIds, ['joao@prosa']);
    expect(viewModel.state.hasError, isTrue);
    expect(viewModel.state.blocksSubmit, isTrue);
    expect(repository.checkedUsers, isEmpty);
  });

  test(
    'usuário inexistente fica vermelho e bloqueia; desconhecido libera',
    () async {
      repository.userChecks['@joao:b.co'] = const UserNotFound();
      repository.userChecks['@rui:b.co'] = const UserUnknown();

      viewModel.queryChanged('@joao:b.co');
      await viewModel.addInvite();
      viewModel.queryChanged('@rui:b.co');
      await viewModel.addInvite();

      expect(chips(), [
        ('@joao:b.co', InviteChipStatus.notFound),
        ('@rui:b.co', InviteChipStatus.unknown),
      ]);
      expect(viewModel.state.notFoundIds, ['@joao:b.co']);
      expect(viewModel.state.unknownIds, ['@rui:b.co']);
      expect(viewModel.state.hasUnknown, isTrue);
      expect(viewModel.state.blocksSubmit, isTrue);

      viewModel.removeInvite(0);
      expect(viewModel.state.hasError, isFalse);
      expect(viewModel.state.hasUnknown, isTrue);
      expect(viewModel.state.blocksSubmit, isFalse);
    },
  );

  test('chip em verificação bloqueia', () async {
    repository.checkUserGate = Completer<void>();
    viewModel.queryChanged('@ana:b.co');

    final adding = viewModel.addInvite();
    expect(chips(), [('@ana:b.co', InviteChipStatus.checking)]);
    expect(viewModel.state.blocksSubmit, isTrue);

    repository.checkUserGate!.complete();
    await adding;
    expect(viewModel.state.blocksSubmit, isFalse);
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

  test('editLastInvite tira o último chip e devolve o id ao texto', () async {
    viewModel.queryChanged('@ana:b.co,');
    viewModel.queryChanged('@bia:b.co,');
    await pumpEventQueue();

    viewModel.editLastInvite();

    expect(chips(), [('@ana:b.co', InviteChipStatus.found)]);
    expect(viewModel.state.query, '@bia:b.co');
  });

  test('editLastInvite sem chips não faz nada', () {
    viewModel.editLastInvite();

    expect(viewModel.state.chips, isEmpty);
    expect(viewModel.state.query, isEmpty);
  });

  test('editLastInvite durante a verificação não recria o chip', () async {
    repository.checkUserGate = Completer<void>();
    viewModel.queryChanged('@ana:b.co');
    final adding = viewModel.addInvite();

    viewModel.editLastInvite();
    repository.checkUserGate!.complete();
    await adding;

    expect(viewModel.state.chips, isEmpty);
    expect(viewModel.state.query, '@ana:b.co');
  });

  test(
    'aceita servidor com porta, localhost, IPv4, IPv6 e hostname simples',
    () async {
      const ids = [
        '@ana:b.co:8448',
        '@alice:localhost',
        '@alice2:localhost:8008',
        '@bob:127.0.0.1',
        '@c:[::1]:8448',
        '@d:synapse',
      ];
      for (final id in ids) {
        viewModel.queryChanged(id);
        await viewModel.addInvite();
      }

      expect(chips(), [for (final id in ids) (id, InviteChipStatus.found)]);
      expect(repository.checkedUsers, ids);
    },
  );

  test('rejeita IDs sem @, sem servidor ou sem localpart', () async {
    const ids = ['alice:localhost', '@alice', '@alice:', '@:localhost'];
    for (final id in ids) {
      viewModel.queryChanged(id);
      await viewModel.addInvite();
    }

    expect(chips(), [
      for (final id in ids) (id, InviteChipStatus.invalidFormat),
    ]);
    expect(repository.checkedUsers, isEmpty);
  });

  test('flush transforma o texto pendente e espera as verificações', () async {
    repository.checkUserGate = Completer<void>();
    viewModel.queryChanged('@ana:b.co @bia:b.co');

    final flushing = viewModel.flush();
    await pumpEventQueue();
    expect(chips(), [
      ('@ana:b.co', InviteChipStatus.checking),
      ('@bia:b.co', InviteChipStatus.checking),
    ]);
    repository.checkUserGate!.complete();
    await flushing;

    expect(viewModel.state.ids, ['@ana:b.co', '@bia:b.co']);
    expect(viewModel.state.blocksSubmit, isFalse);
  });

  test('flush sem texto pendente não muda nada', () async {
    await viewModel.flush();

    expect(viewModel.state, const InviteChipsState());
  });
}
