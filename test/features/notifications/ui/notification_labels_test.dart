import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/notifications/domain/models/room_notification.dart';
import 'package:matrix_messenger/features/notifications/ui/notification_labels.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';

void main() {
  final group = RoomNotification(
    roomId: '!a:b.c',
    roomName: 'lançamento-q4',
    senderName: 'Carla Mendes',
    body: 'Subi a versão\n\nfinal  do deck.',
    timestamp: DateTime(2026, 10, 6, 10),
  );

  test('grupo: título com # e corpo com primeiro nome, em uma linha', () {
    expect(notificationTitle(group), '#lançamento-q4');
    expect(notificationBody(group), 'Carla: Subi a versão final do deck.');
  });

  test('DM: título é a pessoa e o corpo é só o conteúdo', () {
    final direct = RoomNotification(
      roomId: '!d:b.c',
      roomName: 'Ana Ribeiro',
      isDirect: true,
      senderName: 'Ana Ribeiro',
      body: 'oi',
      timestamp: DateTime(2026, 10, 6, 10),
    );

    expect(notificationTitle(direct), 'Ana Ribeiro');
    expect(notificationBody(direct), 'oi');
  });

  test('mídia e mensagem cifrada usam os rótulos da lista', () {
    final image = RoomNotification(
      roomId: '!d:b.c',
      roomName: 'Ana Ribeiro',
      isDirect: true,
      senderName: 'Ana Ribeiro',
      kind: LatestMessageKind.image,
      timestamp: DateTime(2026, 10, 6, 10),
    );
    final encrypted = RoomNotification(
      roomId: '!a:b.c',
      roomName: 'Equipe',
      senderName: 'Diego Alves',
      kind: LatestMessageKind.encrypted,
      timestamp: DateTime(2026, 10, 6, 10),
    );

    expect(notificationBody(image), 'Imagem');
    expect(notificationBody(encrypted), 'Diego: Mensagem criptografada');
  });

  test('convite', () {
    final invite = RoomNotification(
      roomId: '!i:b.c',
      roomName: 'design-system',
      isInvite: true,
      senderName: 'Diego Alves',
      kind: LatestMessageKind.other,
      timestamp: DateTime(2026, 10, 6, 10),
    );

    expect(notificationTitle(invite), '#design-system');
    expect(notificationBody(invite), 'Diego Alves convidou você');
  });

  test('sala sem nome', () {
    final empty = RoomNotification(
      roomId: '!e:b.c',
      roomName: '',
      senderName: 'Bob',
      body: 'oi',
      timestamp: DateTime(2026, 10, 6, 10),
    );

    expect(notificationTitle(empty), '#Sala vazia');
  });
}
