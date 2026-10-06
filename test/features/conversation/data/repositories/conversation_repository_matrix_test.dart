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
    bridge.MessageKind kind = bridge.MessageKind.text,
    bridge.SendState sendState = bridge.SendState.sent,
    bridge.ThreadInfo? thread,
    bridge.ReplyPreview? replyTo,
    List<String> readBy = const [],
  }) => bridge.TimelineMessage(
    id: id,
    senderId: '@bob:b.c',
    senderName: 'Bob',
    isOwn: false,
    timestampMs: 1000,
    kind: kind,
    body: 'oi',
    edited: true,
    sendState: sendState,
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
                state: bridge.ReplyState.ready,
                senderName: 'Ana',
                kind: bridge.MessageKind.image,
              ),
              readBy: ['Ana'],
            ),
          ),
        ],
        reachedStart: true,
      ),
    );

    expect(
      await received,
      ConversationSnapshot(
        items: [
          DateDividerItem(DateTime.fromMillisecondsSinceEpoch(0)),
          MessageItem(
            id: '\$1',
            senderId: '@bob:b.c',
            senderName: 'Bob',
            isOwn: false,
            timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
            kind: MessageKind.text,
            body: 'oi',
            edited: true,
            thread: ThreadSummary(
              rootEventId: '\$1',
              replies: 3,
              latestSender: 'Ana',
              latestAt: DateTime.fromMillisecondsSinceEpoch(2000),
              unread: 2,
            ),
            replyTo: const ReplyPreview(
              state: ReplyState.ready,
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
                replyTo: bridge.ReplyPreview(state: state),
              ),
            ),
        ],
        reachedStart: false,
      ),
    );

    final items = (await received).items.cast<MessageItem>();
    expect(items.map((m) => m.replyTo?.state), ReplyState.values);
  });

  test('ações repassam para o RoomTimeline', () async {
    final conversation = await open();
    timeline.reachedStartOnPaginate = true;

    final older = await conversation.loadOlder();
    expect((older as Ok<bool>).value, isTrue);
    await conversation.send('**oi**');
    await conversation.retry('txn1');
    await conversation.cancel('txn2');
    await conversation.markAsRead();
    final thread = await conversation.openThread('\$root');
    conversation.dispose();

    expect(timeline.sentBodies, ['**oi**']);
    expect(timeline.retried, ['txn1']);
    expect(timeline.cancelled, ['txn2']);
    expect(timeline.markAsReadCalls, 1);
    expect(timeline.openedThreads, ['\$root']);
    expect(thread, isA<Ok<Conversation>>());
    expect(timeline.isDisposed, isTrue);
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
