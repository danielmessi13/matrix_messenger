import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/threads/domain/models/recent_thread.dart';
import 'package:matrix_messenger/features/threads/ui/view_models/recent_threads_state.dart';
import 'package:matrix_messenger/features/threads/ui/view_models/recent_threads_view_model.dart';

import '../../../../../testing/fakes/repositories/fake_recent_threads_repository.dart';
import '../../../../../testing/models/recent_thread.dart';

void main() {
  late FakeRecentThreadsRepository repository;

  setUp(() => repository = FakeRecentThreadsRepository());

  tearDown(() => repository.dispose());

  test('começa carregando e sem threads', () {
    expect(
      RecentThreadsViewModel(repository).state,
      const RecentThreadsState(),
    );
  });

  blocTest<RecentThreadsViewModel, RecentThreadsState>(
    'repassa cada snapshot',
    build: () => RecentThreadsViewModel(repository),
    act: (viewModel) async {
      viewModel.init();
      repository.controller.add(
        RecentThreads(
          status: RecentThreadsStatus.ready,
          threads: [kTeamThread],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      repository.controller.add(
        const RecentThreads(status: RecentThreadsStatus.failed, threads: []),
      );
    },
    expect: () => [
      RecentThreadsState(
        status: RecentThreadsStatus.ready,
        threads: [kTeamThread],
      ),
      const RecentThreadsState(status: RecentThreadsStatus.failed),
    ],
  );

  blocTest<RecentThreadsViewModel, RecentThreadsState>(
    'tentar de novo pede ao repositório',
    build: () => RecentThreadsViewModel(repository),
    act: (viewModel) => viewModel.retry(),
    verify: (_) => expect(repository.retries, 1),
  );
}
