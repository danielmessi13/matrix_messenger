import 'dart:typed_data';

import '../../../../core/services/matrix_service.dart';
import '../../../../core/utils/result.dart';
import '../../../../src/rust/api/media.dart' as bridge;
import '../../domain/models/conversation_failure.dart';
import 'media_repository.dart';

const kMediaCacheBytes = 64 * 1024 * 1024;

class MediaRepositoryMatrix implements MediaRepository {
  MediaRepositoryMatrix(this._service, {this.maxBytes = kMediaCacheBytes});

  final MatrixService _service;

  final int maxBytes;

  final _cache = <String, Uint8List>{};

  final _pending = <String, Future<Result<Uint8List>>>{};

  int _bytes = 0;

  static String _key(String media, bool thumbnail) =>
      '${thumbnail ? 't' : 'o'}:$media';

  @override
  Uint8List? cached(String media, {required bool thumbnail}) {
    final key = _key(media, thumbnail);
    final bytes = _cache.remove(key);
    if (bytes != null) _cache[key] = bytes;
    return bytes;
  }

  @override
  Future<Result<Uint8List>> load(String media, {required bool thumbnail}) {
    if (cached(media, thumbnail: thumbnail) case final bytes?) {
      return Future.value(Result.ok(bytes));
    }
    final key = _key(media, thumbnail);
    return _pending[key] ??= _fetch(key, media, thumbnail).whenComplete(() {
      _pending.remove(key);
    });
  }

  Future<Result<Uint8List>> _fetch(
    String key,
    String media,
    bool thumbnail,
  ) async {
    switch (await _service.loadMedia(media, thumbnail: thumbnail)) {
      case Ok(:final value):
        _store(key, value);
        return Result.ok(value);
      case Error(:final error):
        return Result.error(_toFailure(error));
    }
  }

  void _store(String key, Uint8List bytes) {
    if (bytes.length > maxBytes) return;
    _cache[key] = bytes;
    _bytes += bytes.length;
    while (_bytes > maxBytes) {
      _bytes -= _cache.remove(_cache.keys.first)!.length;
    }
  }
}

ConversationFailure _toFailure(Exception error) => switch (error) {
  bridge.MediaError(:final kind, :final message) => ConversationFailure(
    kind == bridge.MediaErrorKind.network
        ? ConversationFailureType.network
        : ConversationFailureType.unknown,
    message,
  ),
  _ => ConversationFailure(ConversationFailureType.unknown, '$error'),
};
