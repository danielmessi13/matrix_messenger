import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/media_repository.dart';
import 'image_state.dart';

class ImageViewModel extends Cubit<ImageState> {
  ImageViewModel(
    this._repository,
    this._media, {
    required this.thumbnail,
    Uint8List? placeholder,
  }) : super(
         _initial(
           _repository.cached(_media, thumbnail: thumbnail),
           placeholder,
         ),
       );

  final MediaRepository _repository;

  final bool thumbnail;

  String _media;

  static ImageState _initial(Uint8List? cached, Uint8List? placeholder) =>
      cached != null
      ? ImageState(status: ImageStatus.ready, bytes: cached)
      : ImageState(bytes: placeholder);

  Future<void> load() async {
    if (state.status == ImageStatus.ready) return;
    final media = _media;
    emit(ImageState(bytes: state.bytes));
    final result = await _repository.load(media, thumbnail: thumbnail);
    if (isClosed || media != _media) return;
    switch (result) {
      case Ok(:final value):
        emit(ImageState(status: ImageStatus.ready, bytes: value));
      case Error(:final error):
        log('Falha ao carregar a imagem', name: 'conversation', error: error);
        emit(ImageState(status: ImageStatus.failed, bytes: state.bytes));
    }
  }

  Future<void> show(String media) {
    if (media == _media) return load();
    _media = media;
    emit(
      switch (_repository.cached(media, thumbnail: thumbnail)) {
        final bytes? => ImageState(status: ImageStatus.ready, bytes: bytes),
        null => ImageState(bytes: state.bytes),
      },
    );
    return load();
  }
}
