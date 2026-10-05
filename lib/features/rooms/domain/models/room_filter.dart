import 'room.dart';

enum RoomFilter {
  inbox,
  mentions,
  threads,
  rooms,
  direct;

  bool get enabled => this != threads;

  bool matches(Room room) => switch (this) {
    inbox => true,
    mentions => room.unreadMentions > 0,
    threads => false,
    rooms => !room.isDirect,
    direct => room.isDirect,
  };
}
