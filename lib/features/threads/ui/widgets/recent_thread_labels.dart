import '../../../conversation/ui/widgets/message_labels.dart';
import '../../../rooms/domain/models/room.dart';
import '../../../rooms/ui/room_list/widgets/room_labels.dart';
import '../../domain/models/recent_thread.dart';

String threadRootPreview(LatestMessage root) =>
    '${root.isOwn ? 'Você' : firstName(root.senderName)}: ${messageContent(root)}';

String threadActivityLabel(RecentThread thread) {
  final reply = thread.latestReply;
  if (reply == null || thread.replyCount == 0) return 'Nenhuma resposta ainda';
  final who = reply.isOwn ? 'sua' : 'de ${firstName(reply.senderName)}';
  return '${repliesLabel(thread.replyCount)} · última $who às '
      '${formatMessageTime(reply.timestamp)}';
}

String threadLatestPreview(RecentThread thread) => switch (thread.latestReply) {
  null => '',
  final reply => messageContent(reply),
};
