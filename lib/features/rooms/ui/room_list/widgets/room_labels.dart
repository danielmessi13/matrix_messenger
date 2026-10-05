import 'package:flutter/material.dart';

import '../../../domain/models/room.dart';
import '../../../domain/models/room_filter.dart';

const _weekdays = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

String formatRoomTime(DateTime time, DateTime now) {
  // Datas em UTC para a troca de horário de verão não encurtar um dia.
  final day = DateTime.utc(time.year, time.month, time.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';
  if (days == 1) return 'Ontem';
  if (days < 7) return _weekdays[time.weekday - 1];
  return '${_twoDigits(time.day)}/${_twoDigits(time.month)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String roomName(Room room) => room.name.isEmpty ? 'Sala vazia' : room.name;

String roomListLabel(Room room) =>
    room.isDirect ? roomName(room) : '# ${roomName(room)}';

String roomTitle(Room room) =>
    room.isDirect ? roomName(room) : '#${roomName(room)}';

String roomInitials(Room room) =>
    room.isDirect ? initialsOfName(roomName(room)) : '#';

String initialsOfName(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  if (words.length > 1) {
    return (words[0].characters.first + words[1].characters.first)
        .toUpperCase();
  }
  return words.first.characters.take(2).toString().toUpperCase();
}

String _firstName(String name) => name.trim().split(RegExp(r'\s+')).first;

String latestPreview(Room room) {
  final message = room.latest;
  if (message == null) return room.isInvite ? 'Convite para entrar' : '';
  final content = switch (message.kind) {
    LatestMessageKind.text =>
      (message.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim(),
    LatestMessageKind.image => 'Imagem',
    LatestMessageKind.file => 'Arquivo',
    LatestMessageKind.encrypted => 'Mensagem criptografada',
    LatestMessageKind.other => 'Mensagem',
  };
  if (message.isOwn) return 'Você: $content';
  if (room.isDirect) return content;
  return '${_firstName(message.senderName)}: $content';
}

String unreadLabel(int count) => '$count ${count == 1 ? 'nova' : 'novas'}';

String roomMetaLabel(Room room) {
  if (room.isInvite) return 'CONVITE';
  if (room.isDirect) return 'MENSAGEM DIRETA';
  final count = room.memberCount;
  return 'SALA · $count ${count == 1 ? 'MEMBRO' : 'MEMBROS'}';
}

extension RoomFilterLabels on RoomFilter {
  String get title => switch (this) {
    RoomFilter.inbox => 'Caixa de entrada',
    RoomFilter.mentions => 'Menções',
    RoomFilter.threads => 'Threads',
    RoomFilter.rooms => 'Salas',
    RoomFilter.direct => 'Diretas',
  };

  String get shortTitle => this == RoomFilter.inbox ? 'Entrada' : title;

  IconData get icon => switch (this) {
    RoomFilter.inbox => Icons.inbox_outlined,
    RoomFilter.mentions => Icons.alternate_email,
    RoomFilter.threads => Icons.forum_outlined,
    RoomFilter.rooms => Icons.tag,
    RoomFilter.direct => Icons.person_outline,
  };
}
