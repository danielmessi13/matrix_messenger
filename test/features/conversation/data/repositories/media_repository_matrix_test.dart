import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/media_repository_matrix.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation_failure.dart';
import 'package:matrix_messenger/src/rust/api/media.dart' as bridge;

import '../../../../../testing/fakes/services/fake_matrix_service.dart';

void main() {
  late FakeMatrixService service;
  late MediaRepositoryMatrix repository;

  setUp(() {
    service = FakeMatrixService();
    repository = MediaRepositoryMatrix(service, maxBytes: 10);
  });

  Uint8List bytesOf(Result<Uint8List> result) =>
      (result as Ok<Uint8List>).value;

  test('baixa uma vez por fonte e formato', () async {
    final first = await repository.load('abc', thumbnail: true);
    final again = await repository.load('abc', thumbnail: true);
    await repository.load('abc', thumbnail: false);

    expect(identical(bytesOf(first), bytesOf(again)), isTrue);
    expect(repository.cached('abc', thumbnail: true), bytesOf(first));
    expect(service.loadMediaCalls, [('abc', true), ('abc', false)]);
  });

  test('pedidos simultâneos compartilham o download', () async {
    final results = await Future.wait([
      repository.load('abc', thumbnail: true),
      repository.load('abc', thumbnail: true),
    ]);

    expect(service.loadMediaCalls, hasLength(1));
    expect(identical(bytesOf(results[0]), bytesOf(results[1])), isTrue);
  });

  test('falha não fica no cache e vira ConversationFailure', () async {
    service.loadMediaResult = (_, _) => const Result.error(
      bridge.MediaError(kind: bridge.MediaErrorKind.network, message: 'off'),
    );

    final failed = await repository.load('abc', thumbnail: true);
    service.loadMediaResult = (media, _) =>
        Result.ok(Uint8List.fromList(media.codeUnits));
    final retried = await repository.load('abc', thumbnail: true);

    expect(
      (failed as Error<Uint8List>).error,
      isA<ConversationFailure>().having(
        (f) => f.type,
        'type',
        ConversationFailureType.network,
      ),
    );
    expect(retried, isA<Ok<Uint8List>>());
    expect(service.loadMediaCalls, hasLength(2));
  });

  test('passando do limite, sai a menos usada', () async {
    await repository.load('aaaa', thumbnail: true);
    await repository.load('bbbb', thumbnail: true);
    repository.cached('aaaa', thumbnail: true);
    await repository.load('cccc', thumbnail: true);

    expect(repository.cached('aaaa', thumbnail: true), isNotNull);
    expect(repository.cached('bbbb', thumbnail: true), isNull);
    expect(repository.cached('cccc', thumbnail: true), isNotNull);
  });
}
