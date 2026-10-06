import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/conversation/view_models/conversation_state.dart';
import 'package:matrix_messenger/features/conversation/ui/conversation/view_models/conversation_view_model.dart';

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
    expect(viewModel.state.loadingOlder, isTrue);
    completer.complete();
    await Future.wait([first, second]);
    await viewModel.loadOlder();

    expect(conversation.loadOlderCalls, 1);
    expect(viewModel.state.loadingOlder, isFalse);
    expect(viewModel.state.reachedStart, isTrue);
    await viewModel.close();
  });

  test('loadOlder com falha desliga o indicador', () async {
    final viewModel = build();
    await viewModel.open();
    conversation.snapshots.add(kSnapshot);
    await flush();
    conversation.loadOlderResult = const Result.error(
      FakeConversationRepository.notFound,
    );

    await viewModel.loadOlder();

    expect(viewModel.state.loadingOlder, isFalse);
    expect(viewModel.state.reachedStart, isFalse);
    await viewModel.close();
  });

  test('send apara o texto e ignora vazio', () async {
    final viewModel = build();
    await viewModel.open();

    expect(await viewModel.send('   '), isFalse);
    expect(await viewModel.send('  **oi**\n'), isTrue);
    conversation.sendResult = const Result.error(
      FakeConversationRepository.notFound,
    );
    expect(await viewModel.send('falha'), isFalse);

    expect(conversation.sent, ['**oi**', 'falha']);
    await viewModel.close();
  });

  test('retry e cancel repassam o id', () async {
    final viewModel = build();
    await viewModel.open();

    await viewModel.retry('txn1');
    await viewModel.cancel('txn2');

    expect(conversation.retried, ['txn1']);
    expect(conversation.cancelled, ['txn2']);
    await viewModel.close();
  });

  blocTest<ConversationViewModel, ConversationState>(
    'expandir e recolher thread',
    build: build,
    act: (viewModel) => viewModel
      ..toggleThread('\$root')
      ..toggleThread('\$root'),
    expect: () => const [
      ConversationState(expandedThreads: {'\$root'}),
      ConversationState(),
    ],
  );

  test('expandir abre a thread e recolher a libera', () async {
    final thread = FakeConversation();
    conversation.threadResult = Result.ok(thread);
    final viewModel = build();
    await viewModel.open();

    viewModel.toggleThread('\$root');
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.thread('\$root'), isNotNull);
    expect(conversation.openedThreads, ['\$root']);

    viewModel.toggleThread('\$root');
    await Future<void>.delayed(Duration.zero);
    expect(viewModel.thread('\$root'), isNull);
    expect(thread.isDisposed, isTrue);
    await viewModel.close();
  });

  test('fechar a conversa libera as threads abertas', () async {
    final thread = FakeConversation();
    conversation.threadResult = Result.ok(thread);
    final viewModel = build();
    await viewModel.open();
    viewModel.toggleThread('\$root');
    await Future<void>.delayed(Duration.zero);

    await viewModel.close();

    expect(thread.isDisposed, isTrue);
  });

  test('openThread repassa para a conversa aberta', () async {
    final viewModel = build();
    await viewModel.open();

    final thread = await viewModel.openThread('\$root');

    expect(thread, isA<Ok>());
    expect(conversation.openedThreads, ['\$root']);
    await viewModel.close();
  });

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
