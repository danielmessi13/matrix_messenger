import 'dart:developer';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

abstract interface class SystemNotifications {
  Future<void> init({required void Function(String roomId) onTap});

  Future<void> show({
    required String roomId,
    required String title,
    required String body,
  });

  Future<void> cancelAll();
}

class LocalSystemNotifications implements SystemNotifications {
  LocalSystemNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  void Function(String roomId)? _onTap;

  Future<void>? _initialized;

  // Windows/Linux ignoram um segundo initialize: o callback roteia pelo _onTap atual.
  @override
  Future<void> init({required void Function(String roomId) onTap}) {
    _onTap = onTap;
    return _initialized ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(requestBadgePermission: false),
          linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
          windows: WindowsInitializationSettings(
            appName: 'Matrix Messenger',
            appUserModelId: 'com.danielmessias.matrixMessenger',
            guid: 'd3d5cc51-f4a0-49e2-bf92-633f274afbb1',
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload case final roomId?) _onTap?.call(roomId);
        },
      );
    } on Object catch (error) {
      log('Notificações indisponíveis', name: 'notifications', error: error);
    }
  }

  // Um id por sala: a mensagem nova substitui a anterior em vez de empilhar.
  @override
  Future<void> show({
    required String roomId,
    required String title,
    required String body,
  }) => _plugin.show(
    id: roomId.hashCode & 0x7fffffff,
    title: title,
    body: body,
    payload: roomId,
  );

  // Roda no logout: falha do plugin não pode impedir o encerramento.
  @override
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } on Object catch (error) {
      log('Notificações não canceladas', name: 'notifications', error: error);
    }
  }
}
