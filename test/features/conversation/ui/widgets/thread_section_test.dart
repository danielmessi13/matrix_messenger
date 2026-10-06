import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/app/theme.dart';
import 'package:matrix_messenger/core/utils/result.dart';
import 'package:matrix_messenger/features/conversation/domain/models/conversation.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/thread/view_models/thread_view_model.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/thread_section.dart';

import '../../../../../testing/fakes/repositories/fake_conversation_repository.dart';
import '../../../../../testing/models/message.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onToggle,
    ThreadViewModel? viewModel,
    ThreadSummary? summary,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ThreadSection(
          summary: summary ?? kThreadRoot.thread!,
          onToggle: onToggle ?? () {},
          viewModel: viewModel,
        ),
      ),
    ),
  );

  ThreadViewModel opened(Future<Result<Conversation>> Function() openThread) =>
      ThreadViewModel(openThread)..open();

  testWidgets('recolhida mostra o resumo e expandir chama onToggle', (
    tester,
  ) async {
    var toggles = 0;
    await pump(tester, onToggle: () => toggles++);

    expect(find.text('4 respostas'), findsOneWidget);
    expect(find.textContaining('última de Ana às 10:51'), findsOneWidget);
    await tester.tap(find.byKey(const Key('thread_toggle_\$root')));

    expect(toggles, 1);
  });

  testWidgets('expandida carrega e mostra as respostas', (tester) async {
    final thread = FakeConversation();
    await pump(tester, viewModel: opened(() async => Result.ok(thread)));
    expect(find.text('Carregando respostas…'), findsOneWidget);

    thread.snapshots.add(
      ConversationSnapshot(items: [kOtherMessage], reachedStart: true),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Diego Alves'), findsOneWidget);
    expect(find.text('Recolher thread'), findsOneWidget);
  });

  testWidgets('resposta própria que falhou permite tentar de novo', (
    tester,
  ) async {
    final thread = FakeConversation();
    await pump(tester, viewModel: opened(() async => Result.ok(thread)));
    await tester.pump();
    thread.snapshots.add(
      ConversationSnapshot(
        items: [
          MessageItem(
            id: 'txn',
            senderId: '@alice:matrix.org',
            senderName: 'Alice',
            isOwn: true,
            timestamp: DateTime(2026, 10, 4, 10, 30),
            kind: MessageKind.text,
            body: 'resposta',
            edited: true,
            sendState: SendState.failed,
          ),
        ],
        reachedStart: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Não enviada'), findsOneWidget);
    expect(find.textContaining('(editada)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('message_retry')));
    await tester.pump();

    expect(thread.retried, ['txn']);
  });

  testWidgets('falha ao carregar permite tentar de novo', (tester) async {
    var calls = 0;
    final thread = FakeConversation();
    await pump(
      tester,
      viewModel: opened(
        () async => calls++ == 0
            ? const Result.error(FakeConversationRepository.notFound)
            : Result.ok(thread),
      ),
    );
    await tester.pump();

    expect(find.text('Não foi possível carregar as respostas'), findsOneWidget);
    await tester.tap(find.text('Tentar de novo'));
    await tester.pump();

    expect(calls, 2);
  });

  testWidgets('thread longa carrega respostas anteriores', (tester) async {
    final thread = FakeConversation()..loadOlderResult = const Result.ok(true);
    await pump(tester, viewModel: opened(() async => Result.ok(thread)));
    await tester.pump();
    thread.snapshots.add(
      ConversationSnapshot(items: [kOtherMessage], reachedStart: false),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('thread_load_older_\$root')));
    await tester.pump();
    await tester.pump();

    expect(thread.loadOlderCalls, 1);
    expect(find.byKey(const Key('thread_load_older_\$root')), findsNothing);
  });

  testWidgets('recolhida com respostas novas mostra "N novas"', (tester) async {
    final summary = kThreadRoot.thread!;
    await pump(
      tester,
      summary: ThreadSummary(
        rootEventId: summary.rootEventId,
        replies: summary.replies,
        latestSender: summary.latestSender,
        latestAt: summary.latestAt,
        unread: 2,
      ),
    );

    expect(find.text('2 novas'), findsOneWidget);
  });

  testWidgets('recolhida sem respostas novas não mostra o contador', (
    tester,
  ) async {
    await pump(tester);

    expect(find.textContaining('nova'), findsNothing);
  });
}
