import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/data/repositories/conversation_repository_matrix.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation_failure.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/src/rust/api/timeline.dart' as bridge;

import '../../../../../testing/fakes/services/fake_matrix_service.dart';
import '../../../../../testing/fakes/services/fake_room_timeline.dart';

void main() {
  late FakeMatrixService service;
  late FakeRoomTimeline timeline;
  late ConversationRepositoryMatrix repository;

  setUp(() {
    service = FakeMatrixService();
    timeline = FakeRoomTimeline();
    service.openTimelineResult = Result.ok(timeline);
    repository = ConversationRepositoryMatrix(service);
  });

  Future<Conversation> open() async =>
      (await repository.open('!a:b.c') as Ok<Conversation>).value;

  bridge.TimelineMessage bridgeMessage({
    String id = '\$1',
    String? eventId = '\$1',
    bridge.MessageKind kind = bridge.MessageKind.text,
    bridge.SendState sendState = bridge.SendState.sent,
    bool canReply = true,
    bridge.ThreadInfo? thread,
    bridge.ReplyPreview? replyTo,
    List<String> readBy = const [],
  }) => bridge.TimelineMessage(
    id: id,
    eventId: eventId,
    senderId: '@bob:b.c',
    senderName: 'Bob',
    isOwn: false,
    timestampMs: 1000,
    kind: kind,
    body: 'oi',
    edited: true,
    sendState: sendState,
    canReply: canReply,
    thread: thread,
    replyTo: replyTo,
    readBy: readBy,
  );

  test('converte o snapshot da ponte em domínio', () async {
    final conversation = await open();
    final received = conversation.updates.first;
    timeline.snapshots.add(
      bridge.TimelineSnapshot(
        items: [
          const bridge.TimelineEntry(dateDividerMs: 0),
          bridge.TimelineEntry(
            message: bridgeMessage(
              thread: const bridge.ThreadInfo(
                rootEventId: '\$1',
                replies: 3,
                latestSender: 'Ana',
                latestTimestampMs: 2000,
                unread: 2,
              ),
              replyTo: const bridge.ReplyPreview(
                eventId: '\$0',
                state: bridge.ReplyState.ready,
                isOwn: true,
                senderName: 'Ana',
                kind: bridge.MessageKind.image,
              ),
              readBy: ['Ana'],
            ),
          ),
        ],
        reachedStart: true,
        paginating: false,
      ),
    );

    expect(
      await received,
      ConversationSnapshot(
        items: [
          DateDividerItem(DateTime.fromMillisecondsSinceEpoch(0)),
          MessageItem(
            id: '\$1',
            eventId: '\$1',
            senderId: '@bob:b.c',
            senderName: 'Bob',
            isOwn: false,
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            kind: MessageKind.text,
            body: 'oi',
            edited: true,
            canReply: true,
            thread: ThreadSummary(
              rootEventId: '\$1',
              replies: 3,
              latestSender: 'Ana',
              latestAt: DateTime.fromMillisecondsSinceEpoch(2000),
              unread: 2,
            ),
            replyTo: const ReplyPreview(
              eventId: '\$0',
              state: ReplyState.ready,
              isOwn: true,
              senderName: 'Ana',
              kind: MessageKind.image,
            ),
            readBy: const ['Ana'],
          ),
        ],
        reachedStart: true,
      ),
    );
  });

  test('converte cada tipo e cada estado de envio', () async {
    final conversation = await open();
    final received = conversation.updates.first;
    timeline.snapshots.add(
      bridge.TimelineSnapshot(
        items: [
          for (final (i, kind) in bridge.MessageKind.values.indexed)
            bridge.TimelineEntry(
              message: bridgeMessage(id: '\$k$i', kind: kind),
            ),
          for (final (i, state) in bridge.SendState.values.indexed)
            bridge.TimelineEntry(
              message: bridgeMessage(id: '\$s$i', sendState: state),
            ),
        ],
        reachedStart: false,
        paginating: false,
      ),
    );

    final items = (await received).items.cast<MessageItem>();
    expect(items.take(8).map((m) => m.kind), MessageKind.values);
    expect(items.skip(8).map((m) => m.sendState), SendState.values);
  });

  test('converte cada estado da citação', () async {
    final conversation = await open();
    final received = conversation.updates.first;
    timeline.snapshots.add(
      bridge.TimelineSnapshot(
        items: [
          for (final (i, state) in bridge.ReplyState.values.indexed)
            bridge.TimelineEntry(
              message: bridgeMessage(
                id: '\$r$i',
                replyTo: bridge.ReplyPreview(
                  eventId: '\$0',
                  state: state,
                  isOwn: false,
                ),
              ),
            ),
        ],
        reachedStart: false,
        paginating: false,
      ),
    );

    final items = (await received).items.cast<MessageItem>();
    expect(items.map((m) => m.replyTo?.state), ReplyState.values);
  });

  test('converte evento de sala', () async {
    final conversation = await open();
    final received = conversation.updates.first;
    timeline.snapshots.add(
      const bridge.TimelineSnapshot(
        items: [
          bridge.TimelineEntry(
            roomEvent: bridge.RoomEvent(
              id: '\$e1',
              senderName: 'Bob',
              isOwn: false,
              timestampMs: 3000,
              kind: bridge.RoomEventKind.invited,
              targetName: 'Ana',
              targetIsOwn: true,
              value: 'x',
            ),
          ),
        ],
        reachedStart: true,
        paginating: false,
      ),
    );

    expect(
      (await received).items,
      [
        RoomEventItem(
          id: '\$e1',
          senderName: 'Bob',
          isOwn: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(3000),
          kind: RoomEventKind.invited,
          targetName: 'Ana',
          targetIsOwn: true,
          value: 'x',
        ),
      ],
    );
  });

  test('converte cada tipo de evento de sala', () async {
    final conversation = await open();
    final received = conversation.updates.first;
    timeline.snapshots.add(
      bridge.TimelineSnapshot(
        items: [
          for (final (i, kind) in bridge.RoomEventKind.values.indexed)
            bridge.TimelineEntry(
              roomEvent: bridge.RoomEvent(
                id: '\$e$i',
                senderName: 'Bob',
                isOwn: true,
                timestampMs: 0,
                kind: kind,
                targetIsOwn: false,
              ),
            ),
        ],
        reachedStart: false,
        paginating: false,
      ),
    );

    final items = (await received).items.cast<RoomEventItem>();
    expect(items.map((e) => e.kind), RoomEventKind.values);
    expect(items.map((e) => e.isOwn), everyElement(isTrue));
    expect(items.map((e) => e.value), everyElement(isNull));
  });

  test('ações repassam para o RoomTimeline', () async {
    final conversation = await open();
    timeline.reachedStartOnPaginate = true;

    final older = await conversation.loadOlder();
    expect((older as Ok<bool>).value, isTrue);
    await conversation.send('**oi**');
    await conversation.sendReply('re', '\$1');
    await conversation.retry('txn1');
    await conversation.cancel('txn2');
    await conversation.markAsRead();
    final thread = await conversation.openThread('\$root');
    conversation.dispose();

    expect(timeline.sentBodies, ['**oi**']);
    expect(timeline.replies, [('re', '\$1')]);
    expect(timeline.retried, ['txn1']);
    expect(timeline.cancelled, ['txn2']);
    expect(timeline.markAsReadCalls, 1);
    expect(timeline.openedThreads, ['\$root']);
    expect(thread, isA<Ok<Conversation>>());
    expect(timeline.isDisposed, isTrue);
  });

  test('digitação repassa para o RoomTimeline e falha é silenciosa', () async {
    final conversation = await open();
    final names = conversation.typing.first;
    timeline.typingNames.add(['Bob']);

    await conversation.setTyping(true);
    timeline.error = const bridge.TimelineError(
      kind: bridge.TimelineErrorKind.network,
      message: 'offline',
    );
    await conversation.setTyping(false);

    expect(await names, ['Bob']);
    expect(timeline.typingSent, [true]);
  });

  test('TimelineError vira ConversationFailure', () async {
    final conversation = await open();
    timeline.error = const bridge.TimelineError(
      kind: bridge.TimelineErrorKind.network,
      message: 'offline',
    );

    final result = await conversation.loadOlder();

    expect(
      (result as Error<bool>).error,
      isA<ConversationFailure>().having(
        (f) => f.type,
        'type',
        ConversationFailureType.network,
      ),
    );
  });

  test('converte o estado da paginação', () async {
    final conversation = await open();
    final received = conversation.updates.take(2).toList();
    for (final paginating in [false, true]) {
      timeline.snapshots.add(
        bridge.TimelineSnapshot(
          items: const [],
          reachedStart: false,
          paginating: paginating,
        ),
      );
    }

    expect((await received).map((s) => s.paginating), [false, true]);
  });

  test('falha ao abrir vira ConversationFailure', () async {
    service.openTimelineResult = const Result.error(
      bridge.TimelineError(
        kind: bridge.TimelineErrorKind.roomNotFound,
        message: '!a:b.c',
      ),
    );

    final result = await repository.open('!a:b.c');

    expect(
      (result as Error<Conversation>).error,
      isA<ConversationFailure>().having(
        (f) => f.type,
        'type',
        ConversationFailureType.roomNotFound,
      ),
    );
  });
}
