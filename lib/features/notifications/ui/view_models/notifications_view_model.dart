import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/system_notifications.dart';
import '../../data/repositories/notification_repository.dart';
import '../../domain/models/room_notification.dart';
import '../notification_labels.dart';
import 'notifications_state.dart';

class NotificationsViewModel extends Cubit<NotificationsState> {
  NotificationsViewModel(this._repository, this._system)
    : super(const NotificationsState());

  final NotificationRepository _repository;

  final SystemNotifications _system;

  StreamSubscription<RoomNotification>? _notifications;

  // isClosed só vira true depois do cancelAll; fecha a janela da corrida com o init.
  bool _closing = false;

  Future<void> init() async {
    await _system.init(onTap: _onTap);
    if (_closing || isClosed) return;
    _notifications ??= _repository.notifications.listen(
      _onNotification,
      onError: (Object error) =>
          log('Stream de notificações falhou', name: 'notifications', error: error),
    );
  }

  void setWindowFocused(bool focused) =>
      emit(state.copyWith(windowFocused: focused));

  void setOpenRoom(String? roomId) =>
      emit(state.copyWith(openRoomId: () => roomId));

  void tapHandled() => emit(state.copyWith(tappedRoomId: () => null));

  void _onTap(String roomId) {
    if (isClosed) return;
    emit(state.copyWith(tappedRoomId: () => roomId));
  }

  Future<void> _onNotification(RoomNotification item) async {
    if (state.windowFocused && item.roomId == state.openRoomId) return;
    try {
      await _system.show(
        roomId: item.roomId,
        title: notificationTitle(item),
        body: notificationBody(item),
      );
    } on Object catch (error) {
      log('Notificação não exibida', name: 'notifications', error: error);
    }
  }

  // No logout a home fecha; não deixa notificação de outra sessão na central.
  @override
  Future<void> close() async {
    _closing = true;
    await _notifications?.cancel();
    await _system.cancelAll();
    return super.close();
  }
}
