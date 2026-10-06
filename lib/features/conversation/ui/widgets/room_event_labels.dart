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

const _maxGroupKinds = 3;

String roomEventGroupLabel(List<RoomEventItem> events) {
  final first = events.first;
  final byKind = <RoomEventKind, List<RoomEventItem>>{};
  for (final e in events) {
    (byKind[e.kind] ??= []).add(e);
  }
  final oneAuthor = events.every(
    (e) => e.isOwn == first.isOwn && e.senderName == first.senderName,
  );
  if (!oneAuthor || byKind.length > _maxGroupKinds) {
    return '${events.length} eventos da sala';
  }
  final who = first.isOwn ? 'Você' : first.senderName;
  final actions = [
    for (final MapEntry(key: kind, value: same) in byKind.entries)
      _groupedAction(kind, same),
  ];
  final last = actions.removeLast();
  return actions.isEmpty ? '$who $last' : '$who ${actions.join(', ')} e $last';
}

String _groupedAction(RoomEventKind kind, List<RoomEventItem> events) {
  final targets = {
    for (final e in events) e.targetIsOwn ? 'você' : (e.targetName ?? 'alguém'),
  };
  final target = targets.length == 1
      ? targets.single
      : '${targets.length} pessoas';
  final action = switch (kind) {
    RoomEventKind.created => 'criou a sala',
    RoomEventKind.joined => 'entrou na sala',
    RoomEventKind.left => 'saiu da sala',
    RoomEventKind.invited => 'convidou $target',
    RoomEventKind.inviteDeclined => 'recusou o convite',
    RoomEventKind.kicked => 'removeu $target',
    RoomEventKind.banned => 'baniu $target',
    RoomEventKind.unbanned => 'readmitiu $target',
    RoomEventKind.nameChanged => 'mudou o nome da sala',
    RoomEventKind.topicChanged => 'mudou o tópico',
    RoomEventKind.avatarChanged => 'mudou a imagem da sala',
    RoomEventKind.encryptionEnabled => 'ativou a criptografia de ponta a ponta',
    RoomEventKind.displayNameChanged => 'mudou o nome de exibição',
  };
  return events.length > 1 && targets.length == 1
      ? '$action ${events.length} vezes'
      : action;
}
