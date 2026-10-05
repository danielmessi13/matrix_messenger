import 'package:matrix_messenger/features/rooms/domain/models/room.dart';

final kNow = DateTime(2026, 10, 4, 12);

final kTeamRoom = Room(
  id: '!lancamento:matrix.org',
  name: 'lançamento-q4',
  memberCount: 12,
  unreadMessages: 4,
  unreadMentions: 1,
  heroes: const ['Carla Mendes', 'Diego Alves', 'Ana Ribeiro'],
  latest: LatestMessage(
    senderName: 'Carla Mendes',
    isOwn: false,
    kind: LatestMessageKind.text,
    body: 'Subi a versão final do deck.',
    timestamp: DateTime(2026, 10, 4, 10, 42),
  ),
);

final kDirectRoom = Room(
  id: '!ana:matrix.org',
  name: 'Ana Ribeiro',
  isDirect: true,
  memberCount: 2,
  unreadMessages: 2,
  heroes: const ['Ana Ribeiro'],
  latest: LatestMessage(
    senderName: 'Ana Ribeiro',
    isOwn: false,
    kind: LatestMessageKind.text,
    body: 'Valeu! É o #482.',
    timestamp: DateTime(2026, 10, 4, 10, 31),
  ),
);

final kQuietRoom = Room(
  id: '!design:matrix.org',
  name: 'design-system',
  memberCount: 18,
  latest: LatestMessage(
    senderName: 'Alice',
    isOwn: true,
    kind: LatestMessageKind.text,
    body: 'Ótimo, vou atualizar o deck.',
    timestamp: DateTime(2026, 10, 3, 9, 58),
  ),
);

const kInviteRoom = Room(
  id: '!pagamentos:matrix.org',
  name: 'Squad Pagamentos',
  isInvite: true,
);

final kRooms = [kTeamRoom, kDirectRoom, kQuietRoom, kInviteRoom];
