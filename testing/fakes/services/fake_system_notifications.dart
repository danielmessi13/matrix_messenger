import 'dart:async';

import 'package:matrix_messenger/core/services/system_notifications.dart';

class FakeSystemNotifications implements SystemNotifications {
  final shown = <({String roomId, String title, String body})>[];

  int cancelAllCalls = 0;

  Exception? showError;

  Completer<void>? initGate;

  void Function(String roomId)? _onTap;

  void tap(String roomId) => _onTap?.call(roomId);

  @override
  Future<void> init({required void Function(String roomId) onTap}) async {
    _onTap = onTap;
    await initGate?.future;
  }

  @override
  Future<void> show({
    required String roomId,
    required String title,
    required String body,
  }) async {
    if (showError case final error?) throw error;
    shown.add((roomId: roomId, title: title, body: body));
  }

  @override
  Future<void> cancelAll() async => cancelAllCalls++;
}
