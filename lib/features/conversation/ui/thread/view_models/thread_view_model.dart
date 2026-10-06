import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/timeline_item.dart';
import '../../conversation/view_models/message_search.dart';
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

  int _focusSeq = 0;

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
        _updates = value.updates.listen(
          _onSnapshot,
          onError: (Object error) => _onUpdatesFailed('erro', error),
          onDone: () => _onUpdatesFailed('fim', null),
        );
      case Error(:final error):
        log('Falha ao abrir a thread', name: 'conversation', error: error);
        emit(const ThreadState(status: ThreadStatus.failed));
    }
  }

  void _onSnapshot(ConversationSnapshot snapshot) {
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

  void startReply(MessageItem message) =>
      emit(state.copyWith(replyTo: message));

  void cancelReply() => emit(state.copyWith(replyTo: null));

  Future<bool> send(String text) async {
    final thread = _thread;
    if (text.trim().isEmpty || thread == null) return false;
    final target = state.replyTo;
    final eventId = target?.eventId;
    final result = eventId == null
        ? await thread.send(text)
        : await thread.sendReply(text, eventId);
    if (result is! Ok) return false;
    // Se a resposta mudou durante o envio, a nova fica.
    if (!_closing && !isClosed && state.replyTo == target) {
      emit(state.copyWith(replyTo: null));
    }
    return true;
  }

  Future<void> goTo(String eventId) async {
    final id = await searchMessage(
      this,
      eventId: eventId,
      items: (s) => s.replies,
      reachedStart: (s) => s.reachedStart,
      loadOlder: loadOlder,
    );
    if (_closing || isClosed) return;
    emit(state.copyWith(focusRequest: FocusRequest(id, ++_focusSeq)));
  }

  Future<bool> retry(String messageId) async =>
      await _thread?.retry(messageId) is Ok;

  Future<bool> cancel(String messageId) async =>
      await _thread?.cancel(messageId) is Ok;

  Future<bool> toggleReaction(String messageId, String key) async =>
      await _thread?.toggleReaction(messageId, key) is Ok;

  void _onUpdatesFailed(String reason, Object? error) {
    log('Atualizações da thread: $reason', name: 'conversation', error: error);
    if (_closing || isClosed || state.status != ThreadStatus.loading) return;
    _updates?.cancel();
    _updates = null;
    _thread?.dispose();
    _thread = null;
    emit(const ThreadState(status: ThreadStatus.failed));
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _updates?.cancel();
    _thread?.dispose();
    return super.close();
  }
}
