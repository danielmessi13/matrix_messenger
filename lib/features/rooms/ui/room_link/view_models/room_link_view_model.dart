import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/repositories/room_repository.dart';

enum RoomLinkStatus { idle, copying, copied, failure }

class RoomLinkViewModel extends Cubit<RoomLinkStatus> {
  RoomLinkViewModel(
    this._repository,
    this._roomId, {
    Future<void> Function(String text)? writeClipboard,
    this.resetAfter = const Duration(seconds: 2),
  }) : _writeClipboard = writeClipboard ?? _systemClipboard,
       super(RoomLinkStatus.idle);

  final RoomRepository _repository;

  final String _roomId;

  final Future<void> Function(String text) _writeClipboard;

  final Duration resetAfter;

  Timer? _reset;

  static Future<void> _systemClipboard(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<void> copy() async {
    if (isClosed || state == RoomLinkStatus.copying) return;
    _reset?.cancel();
    emit(RoomLinkStatus.copying);

    var copied = false;
    try {
      final link = await _repository.roomLink(_roomId);
      if (link != null) {
        await _writeClipboard(link);
        copied = true;
      }
    } on Object catch (error) {
      log('Copiar o link da sala falhou', name: 'rooms', error: error);
    }
    if (isClosed) return;
    emit(copied ? RoomLinkStatus.copied : RoomLinkStatus.failure);
    _reset = Timer(resetAfter, () {
      if (!isClosed) emit(RoomLinkStatus.idle);
    });
  }

  @override
  Future<void> close() {
    _reset?.cancel();
    return super.close();
  }
}
