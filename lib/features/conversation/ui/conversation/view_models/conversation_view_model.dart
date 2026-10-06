import 'dart:async';
import 'dart:developer';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/conversation_repository.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/conversation_failure.dart';
import '../../../domain/models/timeline_item.dart';
import '../../thread/view_models/thread_view_model.dart';
import 'conversation_state.dart';
import 'message_search.dart';

class ConversationViewModel extends Cubit<ConversationState> {
  ConversationViewModel(this._repository, this.roomId)
    : super(const ConversationState());

  final ConversationRepository _repository;

  final String roomId;

  Conversation? _conversation;

  StreamSubscription<ConversationSnapshot>? _updates;

  String? _latestMessageId;

  // Repetições da rolagem antes de o snapshot dizer que está paginando.
  bool _loadingOlder = false;

  // isClosed só vira true no fim do close(); durante os awaits dele, um open() em andamento ainda passaria na checagem.
  bool _closing = false;

  Future<void>? _opening;

  // Uma thread por vez, no painel; fica aqui para sobreviver aos rebuilds da conversa.
  ThreadViewModel? _thread;

  ThreadViewModel? get thread => _thread;

  int _focusSeq = 0;

  Future<void> open() =>
      _opening ??= _open().whenComplete(() => _opening = null);

  Future<void> _open() async {
    if (_conversation != null || _closing) return;
    if (state.status != ConversationStatus.opening) {
      emit(const ConversationState());
    }
    final result = await _repository.open(roomId);
    if (_closing || isClosed) {
      if (result case Ok(:final value)) value.dispose();
      return;
    }
    switch (result) {
      case Ok(:final value):
        _conversation = value;
        _updates = value.updates.listen(
          _onSnapshot,
          onError: (Object error) => _onUpdatesFailed('erro', error),
          onDone: () => _onUpdatesFailed('fim', null),
        );
      case Error(:final error):
        log('Falha ao abrir a conversa', name: 'conversation', error: error);
        emit(state.copyWith(status: ConversationStatus.failed));
    }
  }

  // True quando a busca rodou sem chegar ao início: uma página só de eventos ocultos não muda o estado, então quem chamou reavalia.
  Future<bool> loadOlder() async {
    final conversation = _conversation;
    if (conversation == null ||
        _loadingOlder ||
        state.paginating ||
        state.reachedStart ||
        state.status != ConversationStatus.ready) {
      return false;
    }
    _loadingOlder = true;
    try {
      final result = await conversation.loadOlder();
      if (_closing || isClosed) return false;
      switch (result) {
        case Ok(:final value):
          emit(
            state.copyWith(
              olderFailed: false,
              reachedStart: state.reachedStart || value,
            ),
          );
          return !value;
        case Error():
          emit(state.copyWith(olderFailed: true));
          return false;
      }
    } finally {
      _loadingOlder = false;
    }
  }

  Future<bool> send(String text) async {
    final conversation = _conversation;
    if (text.trim().isEmpty || conversation == null) return false;
    final target = state.replyTo;
    final eventId = target?.eventId;
    final result = eventId == null
        ? await conversation.send(text)
        : await conversation.sendReply(text, eventId);
    if (result is! Ok) return false;
    // Se a resposta mudou durante o envio, a nova fica.
    if (!_closing && !isClosed && state.replyTo == target) {
      emit(state.copyWith(replyTo: null));
    }
    return true;
  }

  Future<bool> retry(String messageId) async =>
      await _conversation?.retry(messageId) is Ok;

  Future<bool> cancel(String messageId) async =>
      await _conversation?.cancel(messageId) is Ok;

  void openThread(String rootEventId) {
    if (state.openThreadId == rootEventId) return;
    _thread?.close();
    _thread = ThreadViewModel(() => _openThreadTimeline(rootEventId))..open();
    emit(state.copyWith(openThreadId: rootEventId));
  }

  void closeThread() {
    _thread?.close();
    _thread = null;
    emit(state.copyWith(openThreadId: null));
  }

  void toggleThread(String rootEventId) => state.openThreadId == rootEventId
      ? closeThread()
      : openThread(rootEventId);

  void startReply(MessageItem message) =>
      emit(state.copyWith(replyTo: message));

  void cancelReply() => emit(state.copyWith(replyTo: null));

  // Cada rodada do goTo só termina com a página no estado (paginação parada).
  Future<void> _loadOlderSettled() async {
    // Se esperou a busca em andamento, o searchMessage reconfere antes de pedir mais.
    if (state.paginating) return _untilIdle((_) => true);
    final before = state.items;
    await loadOlder();
    if (state.reachedStart) return;
    await _untilIdle((s) => !identical(s.items, before));
  }

  Future<void> _untilIdle(bool Function(ConversationState s) accept) async {
    bool ready(ConversationState s) => !s.paginating && accept(s);
    if (ready(state)) return;
    await stream
        .firstWhere(ready)
        .timeout(kSnapshotWait, onTimeout: () => state)
        .then((_) {}, onError: (Object _) {});
  }

  Future<void> goTo(String eventId) async {
    final id = await searchMessage(
      this,
      eventId: eventId,
      items: (s) => s.items,
      reachedStart: (s) => s.reachedStart,
      loadOlder: _loadOlderSettled,
    );
    if (_closing || isClosed) return;
    emit(state.copyWith(focusRequest: FocusRequest(id, ++_focusSeq)));
  }

  // Esc: resposta na thread, depois resposta na conversa, depois o painel.
  bool escape() {
    final thread = _thread;
    if (thread != null && thread.state.replyTo != null) {
      thread.cancelReply();
    } else if (state.replyTo != null) {
      cancelReply();
    } else if (thread != null) {
      closeThread();
    } else {
      return false;
    }
    return true;
  }

  Future<Result<Conversation>> _openThreadTimeline(String rootEventId) async =>
      await _conversation?.openThread(rootEventId) ??
      const Result.error(ConversationFailure(ConversationFailureType.unknown));

  void _onSnapshot(ConversationSnapshot snapshot) {
    if (_closing || isClosed) return;
    emit(
      state.copyWith(
        status: ConversationStatus.ready,
        items: snapshot.items,
        reachedStart: snapshot.reachedStart,
        paginating: snapshot.paginating,
      ),
    );
    final latest = snapshot.items.whereType<MessageItem>().lastOrNull;
    if (latest != null && latest.id != _latestMessageId && !latest.isOwn) {
      _conversation?.markAsRead();
    }
    _latestMessageId = latest?.id;
  }

  void _onUpdatesFailed(String reason, Object? error) {
    log(
      'Atualizações da conversa: $reason',
      name: 'conversation',
      error: error,
    );
    if (_closing || isClosed || state.status != ConversationStatus.opening) {
      return;
    }
    _updates?.cancel();
    _updates = null;
    _conversation?.dispose();
    _conversation = null;
    emit(state.copyWith(status: ConversationStatus.failed));
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _updates?.cancel();
    await _thread?.close();
    _conversation?.dispose();
    return super.close();
  }
}
