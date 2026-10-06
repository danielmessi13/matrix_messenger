import '../../domain/models/timeline_item.dart';

String roomEventLabel(RoomEventItem e) {
  final who = e.isOwn ? 'Você' : e.senderName;
  final target = e.targetIsOwn ? 'você' : (e.targetName ?? 'alguém');
  return switch (e.kind) {
    RoomEventKind.created => '$who criou a sala',
    RoomEventKind.joined => '$who entrou na sala',
    RoomEventKind.left => '$who saiu da sala',
    RoomEventKind.invited => '$who convidou $target',
    RoomEventKind.inviteDeclined => '$who recusou o convite',
    RoomEventKind.kicked => '$who removeu $target',
    RoomEventKind.banned => '$who baniu $target',
    RoomEventKind.unbanned => '$who readmitiu $target',
    RoomEventKind.nameChanged => switch (e.value) {
      final name? => '$who mudou o nome da sala para “$name”',
      null => '$who removeu o nome da sala',
    },
    RoomEventKind.topicChanged => switch (e.value) {
      final topic? => '$who mudou o tópico para “$topic”',
      null => '$who removeu o tópico',
    },
    RoomEventKind.avatarChanged => '$who mudou a imagem da sala',
    RoomEventKind.encryptionEnabled =>
      '$who ativou a criptografia de ponta a ponta',
    RoomEventKind.displayNameChanged => _displayNameLabel(e),
  };
}

// targetName traz o nome antigo; o remetente já pode estar com o nome novo.
String _displayNameLabel(RoomEventItem e) => switch ((e.targetName, e.value)) {
  (_, _) when e.isOwn => switch (e.value) {
    final name? => 'Você agora se chama $name',
    null => 'Você removeu o nome de exibição',
  },
  (final old?, final name?) => '$old agora se chama $name',
  (null, final name?) => '$name definiu o nome de exibição',
  (final old?, null) => '$old removeu o nome de exibição',
  (null, null) => '${e.senderName} removeu o nome de exibição',
};
