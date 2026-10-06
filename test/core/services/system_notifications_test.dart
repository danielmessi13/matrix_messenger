import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/services/system_notifications.dart';

// Windows/Linux ignoram o segundo initialize e mantêm o primeiro callback.
class _FirstCallbackOnlyPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  int initializeCalls = 0;

  DidReceiveNotificationResponseCallback? kept;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls++;
    kept ??= onDidReceiveNotificationResponse;
    return true;
  }
}

void main() {
  test('init repetido inicializa o plugin uma vez e o clique vai ao último', () async {
    final plugin = _FirstCallbackOnlyPlugin();
    final system = LocalSystemNotifications(plugin);
    final taps = <String>[];

    await system.init(onTap: (roomId) => taps.add('primeiro:$roomId'));
    await system.init(onTap: (roomId) => taps.add('segundo:$roomId'));

    plugin.kept!(
      const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: '!a:b.c',
      ),
    );

    expect(plugin.initializeCalls, 1);
    expect(taps, ['segundo:!a:b.c']);
  });
}
