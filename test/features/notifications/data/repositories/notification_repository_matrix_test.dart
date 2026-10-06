import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/notifications/data/repositories/notification_repository_matrix.dart';
import 'package:matrix_messenger/features/notifications/domain/models/room_notification.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/src/rust/api/notifications.dart' as bridge;
import 'package:matrix_messenger/src/rust/api/rooms.dart' as bridge;

import '../../../../../testing/fakes/services/fake_matrix_service.dart';

void main() {
  late FakeMatrixService service;
  late NotificationRepositoryMatrix repository;

  setUp(() {
    service = FakeMatrixService();
    repository = NotificationRepositoryMatrix(service);
  });

  tearDown(() => service.dispose());

  test('converte a notificação da ponte', () async {
    final received = repository.notifications.first;
    service.notificationsController.add(
      const bridge.RoomNotification(
        roomId: '!a:b.c',
        roomName: 'Equipe',
        isDirect: false,
        isInvite: false,
        senderName: 'Ana Ribeiro',
        kind: bridge.LatestMessageKind.image,
        body: null,
        timestampMs: 1759750000000,
      ),
    );

    expect(
      await received,
      RoomNotification(
        roomId: '!a:b.c',
        roomName: 'Equipe',
        senderName: 'Ana Ribeiro',
        kind: LatestMessageKind.image,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1759750000000),
      ),
    );
  });

  test('converte os campos não padrão', () async {
    final received = repository.notifications.first;
    service.notificationsController.add(
      const bridge.RoomNotification(
        roomId: '!d:b.c',
        roomName: 'Ana',
        isDirect: true,
        isInvite: true,
        senderName: 'Ana Ribeiro',
        kind: bridge.LatestMessageKind.text,
        body: 'oi',
        timestampMs: 1759750000000,
      ),
    );

    expect(
      await received,
      RoomNotification(
        roomId: '!d:b.c',
        roomName: 'Ana',
        isDirect: true,
        isInvite: true,
        senderName: 'Ana Ribeiro',
        kind: LatestMessageKind.text,
        body: 'oi',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1759750000000),
      ),
    );
  });
}
