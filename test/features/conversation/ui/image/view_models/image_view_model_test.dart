import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/conversation/ui/image/view_models/image_state.dart';
import 'package:matrix_messenger/features/conversation/ui/image/view_models/image_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_media_repository.dart';

void main() {
  late FakeMediaRepository repository;

  setUp(() => repository = FakeMediaRepository());

  test('carrega a miniatura e fica pronta', () async {
    final viewModel = ImageViewModel(repository, 'a', thumbnail: true);
    expect(viewModel.state, const ImageState());

    await viewModel.load();

    expect(viewModel.state.status, ImageStatus.ready);
    expect(viewModel.state.bytes, same(repository.bytes));
    expect(repository.loads, [('a', true)]);
  });

  test('em cache começa pronta e não pede de novo', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    repository.cache[('a', true)] = bytes;

    final viewModel = ImageViewModel(repository, 'a', thumbnail: true);
    await viewModel.load();

    expect(
      viewModel.state,
      ImageState(status: ImageStatus.ready, bytes: bytes),
    );
    expect(repository.loads, isEmpty);
  });

  test('falha e tenta de novo', () async {
    repository.failure = FakeMediaRepository.networkFailure;
    final viewModel = ImageViewModel(repository, 'a', thumbnail: true);

    await viewModel.load();
    expect(viewModel.state.status, ImageStatus.failed);
    repository.failure = null;
    await viewModel.load();

    expect(viewModel.state.status, ImageStatus.ready);
  });

  test('o original mostra a miniatura enquanto baixa', () async {
    final preview = Uint8List.fromList([9]);
    repository.pending = Completer<void>();
    final viewModel = ImageViewModel(
      repository,
      'a',
      thumbnail: false,
      placeholder: preview,
    );

    final loading = viewModel.load();
    expect(viewModel.state, ImageState(bytes: preview));
    repository.pending!.complete();
    await loading;

    expect(viewModel.state.bytes, same(repository.bytes));
    expect(repository.loads, [('a', false)]);
  });

  test('trocar de fonte mantém os bytes até os novos chegarem', () async {
    final viewModel = ImageViewModel(repository, 'local', thumbnail: true);
    await viewModel.load();
    final old = viewModel.state.bytes;
    final gate = repository.pending = Completer<void>();

    final stale = viewModel.show('remota');
    expect(viewModel.state, ImageState(bytes: old));
    final newer = Uint8List.fromList([7]);
    repository.bytes = newer;
    gate.complete();
    await stale;

    expect(
      viewModel.state,
      ImageState(status: ImageStatus.ready, bytes: newer),
    );
    expect(repository.loads, [('local', true), ('remota', true)]);
  });
}
