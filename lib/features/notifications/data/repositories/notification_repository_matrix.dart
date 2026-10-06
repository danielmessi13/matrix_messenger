import '../../../../core/services/matrix_service.dart';
import '../../../../src/rust/api/notifications.dart' as bridge;
import '../../../rooms/data/repositories/room_repository_matrix.dart';
import '../../domain/models/room_notification.dart';
import 'notification_repository.dart';

class NotificationRepositoryMatrix implements NotificationRepository {
  NotificationRepositoryMatrix(this._service);

  final MatrixService _service;

  @override
  Stream<RoomNotification> get notifications =>
      _service.watchNotifications().map(_toNotification);

  RoomNotification _toNotification(bridge.RoomNotification item) =>
      RoomNotification(
        roomId: item.roomId,
        roomName: item.roomName,
        isDirect: item.isDirect,
        isInvite: item.isInvite,
        senderName: item.senderName,
        kind: toLatestMessageKind(item.kind),
        body: item.body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(item.timestampMs),
      );
}
