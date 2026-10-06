import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/ui/room_link/view_models/room_link_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_room_repository.dart';

void main() {
  late FakeRoomRepository repository;
  late List<String> written;

  setUp(() {
    repository = FakeRoomRepository();
    written = [];
  });

  tearDown(() => repository.dispose());

  RoomLinkViewModel build({
    Future<void> Function(String)? writeClipboard,
    Duration resetAfter = const Duration(milliseconds: 20),
  }) {
    final viewModel = RoomLinkViewModel(
      repository,
      '!a:b.c',
      writeClipboard: writeClipboard ?? (text) async => written.add(text),
      resetAfter: resetAfter,
    );
    addTearDown(viewModel.close);
    return viewModel;
  }

  test('copia o link da sala e marca copiado', () async {
    final viewModel = build();

    await viewModel.copy();

    expect(repository.roomLinkCalls, ['!a:b.c']);
    expect(written, ['https://matrix.to/#/!a:b.c?via=b.c']);
    expect(viewModel.state, RoomLinkStatus.copied);
  });

  test('volta a idle depois do tempo', () async {
    final viewModel = build();

    await viewModel.copy();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(viewModel.state, RoomLinkStatus.idle);
  });

  test('sem link vira failure e não grava nada', () async {
    repository.roomLinkValue = null;
    final viewModel = build();

    await viewModel.copy();

    expect(viewModel.state, RoomLinkStatus.failure);
    expect(written, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(viewModel.state, RoomLinkStatus.idle);
  });

  test('erro ao gravar na área de transferência vira failure', () async {
    final viewModel = build(
      writeClipboard: (_) async => throw PlatformException(code: 'clipboard'),
    );

    await viewModel.copy();

    expect(viewModel.state, RoomLinkStatus.failure);
  });

  test('repositório que lança vira failure', () async {
    repository.roomLinkError = Exception('sem rede');
    final viewModel = build();

    await viewModel.copy();

    expect(viewModel.state, RoomLinkStatus.failure);
    expect(written, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 40));
  });

  test('copiar de novo enquanto copia é ignorado', () async {
    repository.roomLinkGate = Completer<void>();
    final viewModel = build();

    final first = viewModel.copy();
    expect(viewModel.state, RoomLinkStatus.copying);
    await viewModel.copy();
    repository.roomLinkGate!.complete();
    await first;

    expect(repository.roomLinkCalls, hasLength(1));
  });

  test('fechar cancela a volta para idle', () async {
    final viewModel = build();
    await viewModel.copy();

    await viewModel.close();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(viewModel.state, RoomLinkStatus.copied);
  });
}
