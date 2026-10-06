import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';

final kDay = DateTime(2026, 10, 4);

final kOtherMessage = MessageItem(
  id: '\$other',
  eventId: '\$other',
  senderId: '@diego:matrix.org',
  senderName: 'Diego Alves',
  isOwn: false,
  timestamp: DateTime(2026, 10, 4, 10, 5),
  kind: MessageKind.text,
  canReply: true,
  body: 'A integração com o gateway **novo** ficou pronta.',
);

final kThreadRoot = MessageItem(
  id: '\$root',
  eventId: '\$root',
  senderId: '@carla:matrix.org',
  senderName: 'Carla Mendes',
  isOwn: false,
  timestamp: DateTime(2026, 10, 4, 10, 42),
  kind: MessageKind.text,
  body: 'Subi a versão final do deck.',
  canReply: true,
  thread: ThreadSummary(
    rootEventId: '\$root',
    replies: 4,
    latestSender: 'Ana Ribeiro',
    latestAt: DateTime(2026, 10, 4, 10, 51),
  ),
);

final kOwnMessage = MessageItem(
  id: '\$own',
  eventId: '\$own',
  senderId: '@alice:matrix.org',
  senderName: 'Alice',
  isOwn: true,
  timestamp: DateTime(2026, 10, 4, 10, 21),
  kind: MessageKind.text,
  body: 'Perfeito, rodamos o teste às 15h.',
  canReply: true,
  readBy: const ['Carla Mendes', 'Diego Alves'],
);

final kSnapshot = ConversationSnapshot(
  items: [DateDividerItem(kDay), kOtherMessage, kOwnMessage, kThreadRoot],
  reachedStart: false,
);
