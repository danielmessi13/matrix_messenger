import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/room_event_labels.dart';

void main() {
  String label(
    RoomEventKind kind, {
    String sender = 'Bob',
    bool own = false,
    String? target,
    bool targetOwn = false,
    String? value,
  }) => roomEventLabel(
    RoomEventItem(
      id: '\$e',
      senderName: sender,
      isOwn: own,
      timestamp: DateTime(2026, 10, 4),
      kind: kind,
      targetName: target,
      targetIsOwn: targetOwn,
      value: value,
    ),
  );

  test('eventos de membro', () {
    expect(label(RoomEventKind.created), 'Bob criou a sala');
    expect(label(RoomEventKind.joined), 'Bob entrou na sala');
    expect(label(RoomEventKind.left), 'Bob saiu da sala');
    expect(label(RoomEventKind.invited, target: 'Ana'), 'Bob convidou Ana');
    expect(
      label(RoomEventKind.inviteDeclined, sender: 'Ana'),
      'Ana recusou o convite',
    );
    expect(label(RoomEventKind.kicked, target: 'Ana'), 'Bob removeu Ana');
    expect(label(RoomEventKind.banned, target: 'Ana'), 'Bob baniu Ana');
    expect(label(RoomEventKind.unbanned, target: 'Ana'), 'Bob readmitiu Ana');
  });

  test('o usuário logado vira "Você" e "você"', () {
    expect(label(RoomEventKind.joined, own: true), 'Você entrou na sala');
    expect(
      label(RoomEventKind.invited, own: true, target: 'Ana'),
      'Você convidou Ana',
    );
    expect(
      label(RoomEventKind.invited, target: 'Alice', targetOwn: true),
      'Bob convidou você',
    );
    expect(
      label(RoomEventKind.banned, target: 'Alice', targetOwn: true),
      'Bob baniu você',
    );
  });

  test('nome e tópico da sala, definidos ou removidos', () {
    expect(
      label(RoomEventKind.nameChanged, value: 'Q4'),
      'Bob mudou o nome da sala para “Q4”',
    );
    expect(label(RoomEventKind.nameChanged), 'Bob removeu o nome da sala');
    expect(
      label(RoomEventKind.topicChanged, value: 'Planos'),
      'Bob mudou o tópico para “Planos”',
    );
    expect(label(RoomEventKind.topicChanged), 'Bob removeu o tópico');
  });

  test('imagem e criptografia', () {
    expect(label(RoomEventKind.avatarChanged), 'Bob mudou a imagem da sala');
    expect(
      label(RoomEventKind.encryptionEnabled, own: true),
      'Você ativou a criptografia de ponta a ponta',
    );
  });

  test('nome de exibição', () {
    expect(
      label(
        RoomEventKind.displayNameChanged,
        sender: 'Roberto',
        target: 'Beto',
        value: 'Roberto',
      ),
      'Beto agora se chama Roberto',
    );
    expect(
      label(
        RoomEventKind.displayNameChanged,
        sender: 'Roberto',
        value: 'Roberto',
      ),
      'Roberto definiu o nome de exibição',
    );
    expect(
      label(RoomEventKind.displayNameChanged, sender: 'Beto', target: 'Beto'),
      'Beto removeu o nome de exibição',
    );
    expect(
      label(
        RoomEventKind.displayNameChanged,
        own: true,
        target: 'Beto',
        value: 'Roberto',
      ),
      'Você agora se chama Roberto',
    );
    expect(
      label(RoomEventKind.displayNameChanged, own: true, target: 'Beto'),
      'Você removeu o nome de exibição',
    );
  });
}
