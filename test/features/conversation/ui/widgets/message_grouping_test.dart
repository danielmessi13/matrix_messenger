import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/message_grouping.dart';

import '../../../../../testing/models/message.dart';

void main() {
  MessageItem msg({
    String sender = '@bob:b.c',
    Duration at = Duration.zero,
    ReplyPreview? replyTo,
    bool isOwn = false,
  }) => MessageItem(
    id: '\$${at.inSeconds}',
    senderId: sender,
    senderName: 'Bob',
    isOwn: isOwn,
    timestamp: kDay.add(at),
    kind: MessageKind.text,
    body: 'oi',
    replyTo: replyTo,
  );

  test('mesmo autor a menos de 5 min continua o grupo', () {
    expect(continuesGroup(msg(), msg(at: const Duration(minutes: 4))), isTrue);
  });

  test('a 5 min exatos começa outro grupo', () {
    expect(
      continuesGroup(msg(), msg(at: const Duration(minutes: 5))),
      isFalse,
    );
  });

  test('outro autor começa outro grupo', () {
    expect(
      continuesGroup(
        msg(),
        msg(sender: '@carla:c.d', at: const Duration(minutes: 1)),
      ),
      isFalse,
    );
  });

  test('divisor de dia quebra o grupo', () {
    expect(continuesGroup(DateDividerItem(kDay), msg()), isFalse);
  });

  test('resposta a mim mantém o cabeçalho', () {
    const mine = ReplyPreview(
      eventId: '\$1',
      state: ReplyState.ready,
      isOwn: true,
    );
    const others = ReplyPreview(eventId: '\$1', state: ReplyState.ready);
    const at = Duration(minutes: 1);

    expect(continuesGroup(msg(), msg(at: at, replyTo: mine)), isFalse);
    expect(continuesGroup(msg(), msg(at: at, replyTo: others)), isTrue);
  });

  test('mensagem depois de uma resposta a mim começa outro grupo', () {
    const mine = ReplyPreview(
      eventId: '\$1',
      state: ReplyState.ready,
      isOwn: true,
    );

    expect(
      continuesGroup(
        msg(replyTo: mine),
        msg(at: const Duration(minutes: 1)),
      ),
      isFalse,
    );
  });

  test('minha mensagem depois da minha resposta a mim continua o grupo', () {
    const mine = ReplyPreview(
      eventId: '\$1',
      state: ReplyState.ready,
      isOwn: true,
    );

    expect(
      continuesGroup(
        msg(isOwn: true, replyTo: mine),
        msg(isOwn: true, at: const Duration(minutes: 1)),
      ),
      isTrue,
    );
  });

  test('minha resposta a mim mesmo continua o grupo', () {
    const mine = ReplyPreview(
      eventId: '\$1',
      state: ReplyState.ready,
      isOwn: true,
    );

    expect(
      continuesGroup(
        msg(isOwn: true),
        msg(isOwn: true, at: const Duration(minutes: 1), replyTo: mine),
      ),
      isTrue,
    );
  });

  test('minhas mensagens no mesmo minuto continuam o grupo', () {
    expect(
      continuesGroup(
        msg(isOwn: true),
        msg(isOwn: true, at: const Duration(seconds: 20)),
      ),
      isTrue,
    );
  });

  test('resposta a mim quebra o grupo, mas segue do mesmo autor', () {
    const mine = ReplyPreview(
      eventId: '\$1',
      state: ReplyState.ready,
      isOwn: true,
    );
    final reply = msg(at: const Duration(minutes: 1), replyTo: mine);

    expect(continuesGroup(msg(), reply), isFalse);
    expect(sameSenderNearby(msg(), reply), isTrue);
    expect(sameSenderNearby(msg(sender: '@carla:c.d'), reply), isFalse);
  });

  test('primeiro item não continua nada', () {
    expect(continuesGroup(null, msg()), isFalse);
  });

  test('evento de sala antes da mensagem começa outro grupo', () {
    final event = RoomEventItem(
      id: '\$e',
      senderName: 'Bob',
      isOwn: false,
      timestamp: kDay,
      kind: RoomEventKind.joined,
    );
    expect(continuesGroup(event, msg()), isFalse);
  });

  group('groupRoomEvents', () {
    RoomEventItem event(String id) => RoomEventItem(
      id: id,
      senderName: 'Bob',
      isOwn: false,
      timestamp: kDay,
      kind: RoomEventKind.topicChanged,
    );

    test('dois ou mais eventos seguidos viram um grupo', () {
      final m = msg();
      final (a, b, c) = (event('a'), event('b'), event('c'));

      final rows = groupRoomEvents([m, a, b, c]);

      expect(rows, [
        ItemRow(m),
        RoomEventGroupRow([a, b, c]),
      ]);
      expect((rows.last as RoomEventGroupRow).id, 'a');
    });

    test('evento sozinho continua item', () {
      final m = msg();
      final a = event('a');

      expect(groupRoomEvents([a, m]), [ItemRow(a), ItemRow(m)]);
    });

    test('mensagem ou divisor de dia no meio separa os grupos', () {
      final m = msg();
      final divider = DateDividerItem(kDay);
      final items = [
        event('a'),
        event('b'),
        m,
        event('c'),
        divider,
        event('d'),
        event('e'),
      ];

      expect(groupRoomEvents(items), [
        RoomEventGroupRow([
          items[0] as RoomEventItem,
          items[1] as RoomEventItem,
        ]),
        ItemRow(m),
        ItemRow(items[3]),
        ItemRow(divider),
        RoomEventGroupRow([
          items[5] as RoomEventItem,
          items[6] as RoomEventItem,
        ]),
      ]);
    });

    test('sem itens, sem linhas', () {
      expect(groupRoomEvents(const []), isEmpty);
    });
  });
}
