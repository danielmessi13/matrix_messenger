import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/recent_threads_repository.dart';
import '../../domain/models/recent_thread.dart';
import 'recent_threads_state.dart';

class RecentThreadsViewModel extends Cubit<RecentThreadsState> {
  RecentThreadsViewModel(this._repository) : super(const RecentThreadsState());

  final RecentThreadsRepository _repository;

  StreamSubscription<RecentThreads>? _threads;

  void init() {
    _threads ??= _repository.recentThreads.listen(
      (threads) => emit(
        RecentThreadsState(status: threads.status, threads: threads.threads),
      ),
      onError: (Object error) =>
          log('Threads recentes falharam', name: 'threads', error: error),
    );
  }

  Future<void> retry() => _repository.retry();

  @override
  Future<void> close() async {
    await _threads?.cancel();
    return super.close();
  }
}
