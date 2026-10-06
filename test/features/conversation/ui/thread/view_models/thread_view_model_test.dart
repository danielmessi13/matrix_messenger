import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation_failure.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/conversation/view_models/message_search.dart';
import 'package:matrix_messenger/features/conversation/ui/thread/view_models/thread_state.dart';
import 'package:matrix_messenger/features/conversation/ui/thread/view_models/thread_view_model.dart';

import '../../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../../testing/models/message.dart';

void main() {
  late FakeConversation thread;

  Future<ThreadViewModel> opened() async {
    final viewModel = ThreadViewModel(() async => Result.ok(thread));
    await viewModel.open();
    return viewModel;
  }

  Future<void> push(List<TimelineItem> items) async {
    thread.snapshots.add(
      ConversationSnapshot(items: items, reachedStart: true),
    );
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() => thread = FakeConversation());

  final reply = MessageItem(
    id: 'u1',
    eventId: '\$r1',
    senderId: '@diego:b.c',
    senderName: 'Diego Alves',
    isOwn: false,
    timestamp: DateTime(2026, 10, 4, 10, 5),
    kind: MessageKind.text,
    body: 'resposta',
    canReply: true,
  );

  test('send sem resposta envia na thread', () async {
    final viewModel = await opened();
    await push([reply]);

    expect(await viewModel.send('oi'), isTrue);
    expect(thread.sent, ['oi']);
    expect(thread.sentReplies, isEmpty);
  });

  test('send com resposta cita e limpa a resposta', () async {
    final viewModel = await opened();
    await push([reply]);
    viewModel.startReply(reply);

    expect(viewModel.state.replyTo, reply);
    expect(await viewModel.send('re'), isTrue);
    expect(thread.sentReplies, [('re', '\$r1')]);
    expect(viewModel.state.replyTo, isNull);
  });

  test('falha ao enviar mantém a resposta', () async {
    final viewModel = await opened();
    await push([reply]);
    viewModel.startReply(reply);
    thread.sendResult = const Result.error(
      ConversationFailure(ConversationFailureType.network),
    );

    expect(await viewModel.send('re'), isFalse);
    expect(viewModel.state.replyTo, reply);
  });

  test('cancelReply limpa', () async {
    final viewModel = await opened();
    viewModel
      ..startReply(reply)
      ..cancelReply();

    expect(viewModel.state.replyTo, isNull);
  });

  test('goTo acha a resposta e pede o foco', () async {
    final viewModel = await opened();
    await push([reply]);

    await viewModel.goTo('\$r1');

    expect(viewModel.state.focusRequest, const FocusRequest('u1', 1));
  });

  test('goTo sem a mensagem pede foco nulo', () async {
    final viewModel = await opened();
    await push([reply]);

    await viewModel.goTo('\$nada');

    expect(viewModel.state.focusRequest, const FocusRequest(null, 1));
  });

  blocTest<ThreadViewModel, ThreadState>(
    'abre e mostra só as mensagens',
    build: () => ThreadViewModel(() async => Result.ok(thread)),
    act: (viewModel) async {
      await viewModel.open();
      thread.snapshots.add(
        ConversationSnapshot(
          items: [DateDividerItem(kDay), kOtherMessage],
          reachedStart: true,
        ),
      );
    },
    expect: () => [
      ThreadState(
        status: ThreadStatus.ready,
        replies: [kOtherMessage],
        reachedStart: true,
      ),
    ],
  );

  blocTest<ThreadViewModel, ThreadState>(
    'falha e tenta de novo',
    build: () {
      var calls = 0;
      return ThreadViewModel(
        () async => calls++ == 0
            ? const Result.error(FakeConversationRepository.notFound)
            : Result.ok(thread),
      );
    },
    act: (viewModel) async {
      await viewModel.open();
      await viewModel.open();
    },
    expect: () => const [
      ThreadState(status: ThreadStatus.failed),
      ThreadState(),
    ],
  );

  test('loadOlder pagina a thread e para no início', () async {
    thread.loadOlderResult = const Result.ok(true);
    final viewModel = await opened();
    thread.snapshots.add(
      ConversationSnapshot(items: [kOtherMessage], reachedStart: false),
    );
    await Future<void>.delayed(Duration.zero);

    await viewModel.loadOlder();
    await viewModel.loadOlder();

    expect(thread.loadOlderCalls, 1);
    expect(viewModel.state.reachedStart, isTrue);
    expect(viewModel.state.loadingOlder, isFalse);
    await viewModel.close();
  });

  test('fechar libera a thread', () async {
    final viewModel = ThreadViewModel(() async => Result.ok(thread));
    await viewModel.open();

    await viewModel.close();

    expect(thread.isDisposed, isTrue);
  });

  test('fechado durante a abertura descarta a thread', () async {
    final completer = Completer<void>();
    final viewModel = ThreadViewModel(() async {
      await completer.future;
      return Result<Conversation>.ok(thread);
    });
    final opening = viewModel.open();

    await viewModel.close();
    completer.complete();
    await opening;

    expect(thread.isDisposed, isTrue);
  });

  test('dois open() seguidos abrem uma vez só', () async {
    final completer = Completer<void>();
    var calls = 0;
    final viewModel = ThreadViewModel(() async {
      calls++;
      await completer.future;
      return Result<Conversation>.ok(thread);
    });

    final first = viewModel.open();
    final second = viewModel.open();
    completer.complete();
    await Future.wait([first, second]);

    expect(calls, 1);
    expect(thread.listens, 1);
    await viewModel.close();
  });

  test('close iniciado antes da thread chegar a descarta', () async {
    final pending = Completer<Result<Conversation>>();
    final viewModel = ThreadViewModel(() => pending.future);
    final opening = viewModel.open();

    // A abertura retoma antes da continuação do close, com o Cubit ainda não fechado.
    pending.complete(Result.ok(thread));
    final closing = viewModel.close();
    await Future.wait([opening, closing]);

    expect(thread.isDisposed, isTrue);
    expect(thread.listens, 0);
  });

  test('marca a thread como lida no primeiro snapshot com resposta de outra pessoa', () async {
    final viewModel = await opened();

    await push([kOtherMessage]);

    expect(thread.markAsReadCalls, 1);
    await viewModel.close();
  });

  test('snapshot repetido não marca de novo', () async {
    final viewModel = await opened();

    await push([kOtherMessage]);
    await push([kOtherMessage]);

    expect(thread.markAsReadCalls, 1);
    await viewModel.close();
  });

  test('resposta nova de outra pessoa marca de novo', () async {
    final viewModel = await opened();
    final newReply = MessageItem(
      id: '\$new',
      senderId: '@diego:matrix.org',
      senderName: 'Diego Alves',
      isOwn: false,
      timestamp: DateTime(2026, 10, 4, 10, 30),
      kind: MessageKind.text,
      body: 'Mais uma.',
    );

    await push([kOtherMessage]);
    await push([kOtherMessage, newReply]);

    expect(thread.markAsReadCalls, 2);
    await viewModel.close();
  });

  test('resposta própria não marca', () async {
    final viewModel = await opened();

    await push([kOwnMessage]);

    expect(thread.markAsReadCalls, 0);
    await viewModel.close();
  });

  test('erro no stream antes do primeiro snapshot vira falha', () async {
    final viewModel = await opened();

    thread.snapshots.addError(Exception('rust'));
    await Future<void>.delayed(Duration.zero);

    expect(viewModel.state.status, ThreadStatus.failed);
    expect(thread.isDisposed, isTrue);
    await viewModel.close();
  });

  test('retry e cancel repassam o id e o resultado', () async {
    final viewModel = await opened();
    thread.cancelResult = const Result.error(
      FakeConversationRepository.notFound,
    );

    expect(await viewModel.retry('txn1'), isTrue);
    expect(await viewModel.cancel('txn2'), isFalse);

    expect(thread.retried, ['txn1']);
    expect(thread.cancelled, ['txn2']);
    await viewModel.close();
  });

  test('toggleReaction repassa o id e o resultado', () async {
    final viewModel = await opened();

    expect(await viewModel.toggleReaction('\$r1', '❤️'), isTrue);
    thread.reactResult = const Result.error(
      FakeConversationRepository.notFound,
    );
    expect(await viewModel.toggleReaction('\$r1', '❤️'), isFalse);

    expect(thread.reacted, [('\$r1', '❤️'), ('\$r1', '❤️')]);
    await viewModel.close();
  });
}
