import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/threads/domain/models/recent_thread.dart';

import 'room.dart';

final kTeamThread = RecentThread(
  roomId: kTeamRoom.id,
  rootEventId: r'$raiz-time',
  root: LatestMessage(
    senderName: 'Carla Mendes',
    isOwn: false,
    kind: LatestMessageKind.text,
    body: 'Quem revisa o deck?',
    timestamp: DateTime(2026, 10, 4, 9),
  ),
  latestReply: LatestMessage(
    senderName: 'Diego Alves',
    isOwn: false,
    kind: LatestMessageKind.text,
    body: 'Eu pego a parte de números.',
    timestamp: DateTime(2026, 10, 4, 11, 5),
  ),
  replyCount: 3,
  activity: DateTime(2026, 10, 4, 11, 5),
);

final kDirectThread = RecentThread(
  roomId: kDirectRoom.id,
  rootEventId: r'$raiz-ana',
  root: LatestMessage(
    senderName: 'Daniel',
    isOwn: true,
    kind: LatestMessageKind.text,
    body: 'Viu o contrato?',
    timestamp: DateTime(2026, 10, 3, 18),
  ),
  replyCount: 0,
  activity: DateTime(2026, 10, 3, 18),
);
