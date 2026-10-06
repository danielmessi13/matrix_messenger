import '../../domain/models/room_notification.dart';

abstract interface class NotificationRepository {
  Stream<RoomNotification> get notifications;
}
