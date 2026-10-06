import 'dart:typed_data';

import '../../../../core/utils/result.dart';

abstract interface class MediaRepository {
  Future<Result<Uint8List>> load(String media, {required bool thumbnail});

  Uint8List? cached(String media, {required bool thumbnail});
}
