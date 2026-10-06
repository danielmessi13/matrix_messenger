import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/media_repository.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation_failure.dart';

final kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class FakeMediaRepository implements MediaRepository {
  final cache = <(String, bool), Uint8List>{};

  final loads = <(String, bool)>[];

  Completer<void>? pending;

  Uint8List bytes = kTinyPng;

  Exception? failure;

  @override
  Uint8List? cached(String media, {required bool thumbnail}) =>
      cache[(media, thumbnail)];

  @override
  Future<Result<Uint8List>> load(
    String media, {
    required bool thumbnail,
  }) async {
    loads.add((media, thumbnail));
    await pending?.future;
    if (failure case final failure?) return Result.error(failure);
    return Result.ok(bytes);
  }

  static const networkFailure = ConversationFailure(
    ConversationFailureType.network,
  );
}
