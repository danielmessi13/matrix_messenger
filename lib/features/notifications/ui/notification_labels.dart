import '../../rooms/ui/room_list/widgets/room_labels.dart';
import '../domain/models/room_notification.dart';

String notificationTitle(RoomNotification item) {
  final name = item.roomName.isEmpty ? 'Sala vazia' : item.roomName;
  return item.isDirect ? name : '#$name';
}

String notificationBody(RoomNotification item) {
  if (item.isInvite) return '${item.senderName} convidou você';
  final content = messageKindLabel(item.kind, item.body);
  return item.isDirect ? content : '${firstName(item.senderName)}: $content';
}
