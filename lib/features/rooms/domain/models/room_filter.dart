import 'room.dart';

enum RoomFilter {
  inbox,
  mentions,
  threads,
  rooms,
  direct;

  bool matches(Room room) => switch (this) {
    inbox => true,
    mentions => room.unreadMentions > 0,
    threads => room.unreadThreadReplies > 0,
    rooms => !room.isDirect,
    direct => room.isDirect,
  };

  int unreadOf(Room room) => switch (this) {
    threads => room.unreadThreadReplies,
    _ => room.unreadMessages,
  };
}
