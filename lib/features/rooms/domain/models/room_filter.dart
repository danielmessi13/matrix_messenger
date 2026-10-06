import 'room.dart';

enum RoomFilter {
  inbox,
  mentions,
  threads,
  rooms,
  direct;

  // Threads mostra a lista de threads recentes, não salas.
  bool matches(Room room) => switch (this) {
    inbox => true,
    mentions => room.unreadMentions > 0,
    threads => false,
    rooms => !room.isDirect,
    direct => room.isDirect,
  };

  int unreadOf(Room room) => switch (this) {
    mentions => room.unreadMentions,
    threads => 0,
    _ => room.unreadMessages,
  };
}
