import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/message_grouping.dart';

import '../../../../../testing/models/message.dart';

void main() {
  MessageItem msg({
    String sender = '@bob:b.c',
    Duration at = Duration.zero,
    ReplyPreview? replyTo,
  }) => MessageItem(
    id: '\$${at.inSeconds}',
    senderId: sender,
    senderName: 'Bob',
    isOwn: false,
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
}
