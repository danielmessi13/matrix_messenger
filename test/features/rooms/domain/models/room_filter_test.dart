import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room_filter.dart';

void main() {
  const group = Room(id: '!g:b.c', name: 'geral');
  const mentioned = Room(id: '!m:b.c', name: 'time', unreadMentions: 2);
  const direct = Room(id: '!d:b.c', name: 'Ana', isDirect: true);

  final cases = <(RoomFilter, Room, bool)>[
    (RoomFilter.inbox, group, true),
    (RoomFilter.inbox, direct, true),
    (RoomFilter.mentions, group, false),
    (RoomFilter.mentions, mentioned, true),
    (RoomFilter.threads, group, false),
    (RoomFilter.threads, direct, false),
    (RoomFilter.rooms, group, true),
    (RoomFilter.rooms, direct, false),
    (RoomFilter.direct, group, false),
    (RoomFilter.direct, direct, true),
  ];

  for (final (filter, room, expected) in cases) {
    test('${filter.name} com ${room.name} → $expected', () {
      expect(filter.matches(room), expected);
    });
  }

  test('só Threads fica desabilitado', () {
    expect(RoomFilter.values.where((filter) => !filter.enabled), [
      RoomFilter.threads,
    ]);
  });
}
