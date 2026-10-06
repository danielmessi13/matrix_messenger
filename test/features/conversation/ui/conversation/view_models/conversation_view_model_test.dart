import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/conversation/view_models/conversation_state.dart';
import 'package:matrix_messenger/features/conversation/ui/conversation/view_models/conversation_view_model.dart';
import 'package:matrix_messenger/features/conversation/ui/conversation/view_models/message_search.dart';

import '../../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../../testing/models/message.dart';

void main() {
  late FakeConversation conversation;
  late FakeConversationRepository repository;

  setUp(() {
    conversation = FakeConversation();
    repository = FakeConversationRepository(conversation: conversation);
  });

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  ConversationViewModel build() => ConversationViewModel(repository, '!a:b.c');

  test('começa abrindo', () {
    expect(build().state, const ConversationState());
  });

  blocTest<ConversationViewModel, ConversationState>(
    'primeiro snapshot deixa pronta e marca como lida',
    build: build,
    act: (viewModel) async {
      await viewModel.open();
      conversation.snapshots.add(kSnapshot);
    },
    expect: () => [
      ConversationState(
        status: ConversationStatus.ready,
        items: kSnapshot.items,
      ),
    ],
    verify: (_) {
      expect(repository.openedRooms, ['!a:b.c']);
      expect(conversation.markAsReadCalls, 1);
    },
  );

  blocTest<ConversationViewModel, ConversationState>(
    'falha ao abrir e tentar de novo',
    build: () {
      repository.openFailure = FakeConversationRepository.notFound;
      return build();
    },
    act: (viewModel) async {
      await viewModel.open();
      repository.openFailure = null;
      await viewModel.open();
    },
    expect: () => const [
      ConversationState(status: ConversationStatus.failed),
      ConversationState(),
    ],
  );

  test(
    'mensagem nova de outra pessoa marca como lida; a própria não',
    () async {
      final viewModel = build();
      await viewModel.open();
      conversation.snapshots.add(
        ConversationSnapshot(items: [kOtherMessage], reachedStart: false),
      );
      await flush();
      conversation.snapshots.add(
        ConversationSnapshot(items: [kOtherMessage], reachedStart: false),
      );
      await flush();
      conversation.snapshots.add(
        ConversationSnapshot(
          items: [kOtherMessage, kOwnMessage],
          reachedStart: false,
        ),
      );
      await flush();
      conversation.snapshots.add(
        ConversationSnapshot(
          items: [kOtherMessage, kOwnMessage, kThreadRoot],
          reachedStart: false,
        ),
      );
      await flush();

      expect(conversation.markAsReadCalls, 2);
      await viewModel.close();
    },
  );

  test('loadOlder faz uma requisição por vez e para no início', () async {
    final viewModel = build();
    await viewModel.open();
    conversation.snapshots.add(kSnapshot);
    await flush();
    final completer = conversation.loadOlderCompleter = Completer<void>();
    conversation.loadOlderResult = const Result.ok(true);

    final first = viewModel.loadOlder();
    final second = viewModel.loadOlder();
    completer.complete();
    await Future.wait([first, second]);
    await viewModel.loadOlder();

    expect(conversation.loadOlderCalls, 1);
    expect(viewModel.state.reachedStart, isTrue);
    await viewModel.close();
  });

  test('loadOlder diz se vale pedir de novo', () async {
    final viewModel = build();
    expect(await viewModel.loadOlder(), isFalse);
    await viewModel.open();
    conversation.snapshots.add(kSnapshot);
    await flush();

    conversation.loadOlderResult = const Result.ok(false);
    expect(await viewModel.loadOlder(), isTrue);
    conversation.loadOlderResult = const Result.error(
      FakeConversationRepository.notFound,
    );
    expect(await viewModel.loadOlder(), isFalse);
    conversation.loadOlderResult = const Result.ok(true);
    expect(await viewModel.loadOlder(), isFalse);
    expect(await viewModel.loadOlder(), isFalse);

    expect(conversation.loadOlderCalls, 3);
    await viewModel.close();
  });

  test('loadOlder durante a paginação é ignorado', () async {
    final viewModel = build();
    await viewModel.open();
    conversation.snapshots.add(
      ConversationSnapshot(
        items: kSnapshot.items,
        reachedStart: false,
        paginating: true,
      ),
    );
    await flush();

    await viewModel.loadOlder();

    expect(conversation.loadOlderCalls, 0);
    expect(viewModel.state.paginating, isTrue);
    await viewModel.close();
  });

  test('falha no loadOlder liga olderFailed e o sucesso desliga', () async {
    final viewModel = build();
    await viewModel.open();
    conversation.snapshots.add(kSnapshot);
    await flush();
    conversation.loadOlderResult = const Result.error(
      FakeConversationRepository.notFound,
    );

    await viewModel.loadOlder();

    expect(viewModel.state.olderFailed, isTrue);
    expect(viewModel.state.reachedStart, isFalse);
    conversation.loadOlderResult = const Result.ok(false);
    await viewModel.loadOlder();
    expect(viewModel.state.olderFailed, isFalse);
    expect(conversation.loadOlderCalls, 2);
    await viewModel.close();
  });

  test('send ignora vazio e envia o texto sem aparar', () async {
    final viewModel = build();
    await viewModel.open();

    expect(await viewModel.send('   '), isFalse);
    expect(await viewModel.send('  **oi**\n'), isTrue);
    conversation.sendResult = const Result.error(
      FakeConversationRepository.notFound,
    );
    expect(await viewModel.send('falha'), isFalse);

    expect(conversation.sent, ['  **oi**\n', 'falha']);
    await viewModel.close();
  });

  test('retry e cancel repassam o id', () async {
    final viewModel = build();
    await viewModel.open();

    expect(await viewModel.retry('txn1'), isTrue);
    expect(await viewModel.cancel('txn2'), isTrue);

    expect(conversation.retried, ['txn1']);
    expect(conversation.cancelled, ['txn2']);
    await viewModel.close();
  });

  test('retry e cancel devolvem false quando falham', () async {
    final viewModel = build();
    await viewModel.open();
    conversation
      ..retryResult = const Result.error(FakeConversationRepository.notFound)
      ..cancelResult = const Result.error(FakeConversationRepository.notFound);

    expect(await viewModel.retry('txn1'), isFalse);
    expect(await viewModel.cancel('txn2'), isFalse);
    await viewModel.close();
  });

  test(
    'erro no stream antes do primeiro snapshot vira falha e reabre',
    () async {
      final viewModel = build();
      await viewModel.open();

      conversation.snapshots.addError(Exception('rust'));
      await flush();

      expect(viewModel.state.status, ConversationStatus.failed);
      expect(conversation.isDisposed, isTrue);

      final next = FakeConversation();
      repository.conversation = next;
      await viewModel.open();
      next.snapshots.add(kSnapshot);
      await flush();

      expect(viewModel.state.status, ConversationStatus.ready);
      await viewModel.close();
    },
  );

  test('stream que fecha antes do primeiro snapshot vira falha', () async {
    final viewModel = build();
    await viewModel.open();

    await conversation.snapshots.close();
    await flush();

    expect(viewModel.state.status, ConversationStatus.failed);
    await viewModel.close();
  });

  test('erro no stream depois de pronta mantém a timeline', () async {
    final viewModel = build();
    await viewModel.open();
    conversation.snapshots.add(kSnapshot);
    await flush();

    conversation.snapshots.addError(Exception('rust'));
    await flush();

    expect(viewModel.state.status, ConversationStatus.ready);
    expect(conversation.isDisposed, isFalse);
    await viewModel.close();
  });

  Future<ConversationViewModel> ready() async {
    final viewModel = build();
    await viewModel.open();
    conversation.snapshots.add(kSnapshot);
    await flush();
    return viewModel;
  }

  test('openThread abre uma thread só e trocar libera a anterior', () async {
    final first = FakeConversation();
    final viewModel = await ready();
    conversation.threadResult = Result.ok(first);

    viewModel.openThread('\$root');
    await flush();
    expect(viewModel.state.openThreadId, '\$root');
    expect(viewModel.thread, isNotNull);
    conversation.threadResult = Result.ok(FakeConversation());
    viewModel.openThread('\$other');
    await flush();

    expect(viewModel.state.openThreadId, '\$other');
    expect(first.isDisposed, isTrue);
    expect(conversation.openedThreads, ['\$root', '\$other']);
  });

  test('toggleThread fecha a thread aberta', () async {
    final opened = FakeConversation();
    final viewModel = await ready();
    conversation.threadResult = Result.ok(opened);

    viewModel.toggleThread('\$root');
    await flush();
    viewModel.toggleThread('\$root');
    await flush();

    expect(viewModel.state.openThreadId, isNull);
    expect(viewModel.thread, isNull);
    expect(opened.isDisposed, isTrue);
  });

  test('fechar a conversa libera a thread aberta', () async {
    final opened = FakeConversation();
    final viewModel = await ready();
    conversation.threadResult = Result.ok(opened);
    viewModel.openThread('\$root');
    await flush();

    await viewModel.close();

    expect(opened.isDisposed, isTrue);
  });

  test('send com resposta usa sendReply e limpa', () async {
    final viewModel = await ready();
    viewModel.startReply(kOtherMessage);

    expect(await viewModel.send('re'), isTrue);
    expect(conversation.sentReplies, [('re', '\$other')]);
    expect(viewModel.state.replyTo, isNull);
  });

  test('goTo acha a mensagem carregada', () async {
    final viewModel = await ready();

    await viewModel.goTo('\$own');

    expect(viewModel.state.focusRequest, const FocusRequest('\$own', 1));
  });

  test('goTo pagina e avisa quando não acha', () async {
    final viewModel = await ready();
    conversation.loadOlderResult = const Result.ok(true);

    await viewModel.goTo('\$antiga');

    expect(conversation.loadOlderCalls, greaterThanOrEqualTo(1));
    expect(viewModel.state.focusRequest?.messageId, isNull);
  });

  MessageItem messageWith(String id) => MessageItem(
    id: id,
    eventId: id,
    senderId: '@diego:matrix.org',
    senderName: 'Diego Alves',
    isOwn: false,
    timestamp: DateTime(2026, 10, 3),
    kind: MessageKind.text,
    body: id,
  );

  test(
    'goTo acha citação 2 páginas atrás com a página depois da busca',
    () async {
      final viewModel = await ready();
      conversation.loadOlderResult = const Result.ok(false);
      final loaded = <TimelineItem>[...kSnapshot.items];
      void push(bool paginating, List<TimelineItem> items) =>
          conversation.snapshots.add(
            ConversationSnapshot(
              items: List.of(items),
              reachedStart: false,
              paginating: paginating,
            ),
          );
      conversation.onLoadOlder = () {
        push(true, loaded);
        final page = conversation.loadOlderCalls == 1
            ? messageWith('\$p1')
            : messageWith('\$alvo');
        loaded.insert(0, page);
        Future<void>.delayed(
          Duration.zero,
          () => push(false, loaded),
        );
      };

      await viewModel.goTo('\$alvo');

      expect(viewModel.state.focusRequest?.messageId, isNotNull);
      expect(conversation.loadOlderCalls, 2);
      await viewModel.close();
    },
  );

  test(
    'goTo durante a paginação espera ela parar sem chamar loadOlder',
    () async {
      final viewModel = build();
      await viewModel.open();
      conversation.snapshots.add(
        ConversationSnapshot(
          items: kSnapshot.items,
          reachedStart: false,
          paginating: true,
        ),
      );
      await flush();
      Timer(const Duration(milliseconds: 50), () {
        conversation.snapshots.add(
          ConversationSnapshot(
            items: [messageWith('\$alvo'), ...kSnapshot.items],
            reachedStart: false,
          ),
        );
      });

      await viewModel.goTo('\$alvo');

      expect(viewModel.state.focusRequest?.messageId, isNotNull);
      expect(conversation.loadOlderCalls, 0);
      await viewModel.close();
    },
  );

  test('o estado copia paginating de cada snapshot', () async {
    final viewModel = await ready();
    conversation.snapshots.add(
      ConversationSnapshot(
        items: kSnapshot.items,
        reachedStart: false,
        paginating: true,
      ),
    );
    await flush();
    expect(viewModel.state.paginating, isTrue);

    conversation.snapshots.add(
      ConversationSnapshot(items: kSnapshot.items, reachedStart: false),
    );
    await flush();
    expect(viewModel.state.paginating, isFalse);
    await viewModel.close();
  });

  test(
    'escape cancela a resposta da thread, depois a da conversa, depois fecha',
    () async {
      final opened = FakeConversation();
      final viewModel = await ready();
      conversation.threadResult = Result.ok(opened);
      viewModel
        ..startReply(kOtherMessage)
        ..openThread('\$root');
      await flush();
      viewModel.thread!.startReply(kOwnMessage);

      expect(viewModel.escape(), isTrue);
      expect(viewModel.thread!.state.replyTo, isNull);
      expect(viewModel.state.replyTo, kOtherMessage);
      expect(viewModel.escape(), isTrue);
      expect(viewModel.state.replyTo, isNull);
      expect(viewModel.escape(), isTrue);
      expect(viewModel.state.openThreadId, isNull);
      expect(viewModel.escape(), isFalse);
    },
  );

  test('fechar cancela e libera a conversa', () async {
    final viewModel = build();
    await viewModel.open();

    await viewModel.close();

    expect(conversation.isDisposed, isTrue);
    expect(conversation.snapshots.hasListener, isFalse);
  });

  test('fechado durante a abertura descarta a conversa que chegar', () async {
    final completer = repository.openCompleter = Completer<void>();
    final viewModel = build();
    final opening = viewModel.open();

    await viewModel.close();
    completer.complete();
    await opening;

    expect(conversation.isDisposed, isTrue);
    expect(conversation.snapshots.hasListener, isFalse);
  });

  test('dois open() seguidos abrem uma vez só', () async {
    final completer = repository.openCompleter = Completer<void>();
    final viewModel = build();

    final first = viewModel.open();
    final second = viewModel.open();
    completer.complete();
    await Future.wait([first, second]);

    expect(repository.openedRooms, ['!a:b.c']);
    expect(conversation.listens, 1);
    await viewModel.close();
  });

  test('close iniciado antes da conversa chegar a descarta', () async {
    final pending = repository.pendingOpen = Completer<Result<Conversation>>();
    final viewModel = build();
    final opening = viewModel.open();

    // A abertura retoma antes da continuação do close, com o Cubit ainda não fechado.
    pending.complete(Result.ok(conversation));
    final closing = viewModel.close();
    await Future.wait([opening, closing]);

    expect(conversation.isDisposed, isTrue);
    expect(conversation.listens, 0);
  });
}
