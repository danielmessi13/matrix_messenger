import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/timeline_item.dart';
import 'thread_state.dart';

class ThreadViewModel extends Cubit<ThreadState> {
  ThreadViewModel(this._openThread) : super(const ThreadState());

  final Future<Result<Conversation>> Function() _openThread;

  Conversation? _thread;

  StreamSubscription<ConversationSnapshot>? _updates;

  // O close() só marca isClosed no fim; até lá uma abertura que volte ainda acharia o Cubit aberto.
  bool _closing = false;

  Future<void>? _opening;

  String? _latestReplyId;

  Future<void> open() =>
      _opening ??= _open().whenComplete(() => _opening = null);

  Future<void> _open() async {
    if (_thread != null || _closing) return;
    if (state.status != ThreadStatus.loading) emit(const ThreadState());
    final result = await _openThread();
    if (_closing || isClosed) {
      if (result case Ok(:final value)) value.dispose();
      return;
    }
    switch (result) {
      case Ok(:final value):
        _thread = value;
        _updates = value.updates.listen((snapshot) {
          if (_closing || isClosed) return;
          final replies = snapshot.items.whereType<MessageItem>().toList();
          emit(
            state.copyWith(
              status: ThreadStatus.ready,
              replies: replies,
              reachedStart: snapshot.reachedStart,
            ),
          );
          // Expandir é o que marca a thread como lida, como na conversa principal.
          final latest = replies.lastOrNull;
          if (latest != null && latest.id != _latestReplyId && !latest.isOwn) {
            _thread?.markAsRead();
          }
          _latestReplyId = latest?.id;
        });
      case Error(:final error):
        log('Falha ao abrir a thread', name: 'conversation', error: error);
        emit(const ThreadState(status: ThreadStatus.failed));
    }
  }

  Future<void> loadOlder() async {
    final thread = _thread;
    if (thread == null ||
        state.loadingOlder ||
        state.reachedStart ||
        state.status != ThreadStatus.ready) {
      return;
    }
    emit(state.copyWith(loadingOlder: true));
    final result = await thread.loadOlder();
    if (_closing || isClosed) return;
    final reached = result is Ok<bool> && result.value;
    emit(
      state.copyWith(
        loadingOlder: false,
        reachedStart: state.reachedStart || reached,
      ),
    );
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _updates?.cancel();
    _thread?.dispose();
    return super.close();
  }
}
