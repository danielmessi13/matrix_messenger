import 'dart:async';

import 'package:matrix_messenger/features/notifications/data/repositories/notification_repository.dart';
import 'package:matrix_messenger/features/notifications/domain/models/room_notification.dart';

class FakeNotificationRepository implements NotificationRepository {
  final notificationsController =
      StreamController<RoomNotification>.broadcast();

  @override
  Stream<RoomNotification> get notifications => notificationsController.stream;

  Future<void> dispose() => notificationsController.close();
}
