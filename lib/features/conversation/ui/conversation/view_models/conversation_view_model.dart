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

class ConversationViewModel extends Cubit<ConversationState> {
  ConversationViewModel(this._repository, this.roomId)
    : super(const ConversationState());

  final ConversationRepository _repository;

  final String roomId;

  Conversation? _conversation;

  StreamSubscription<ConversationSnapshot>? _updates;

  String? _latestMessageId;

  // isClosed só vira true no fim do close(); durante os awaits dele, um open() em andamento ainda passaria na checagem.
  bool _closing = false;

  Future<void>? _opening;

  // Fora da lista, que é lazy: a thread aberta sobrevive a sair da tela na rolagem.
  final _threads = <String, ThreadViewModel>{};

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

  Future<void> loadOlder() async {
    final conversation = _conversation;
    if (conversation == null ||
        state.loadingOlder ||
        state.reachedStart ||
        state.status != ConversationStatus.ready) {
      return;
    }
    emit(state.copyWith(loadingOlder: true));
    final result = await conversation.loadOlder();
    if (isClosed) return;
    final reached = result is Ok<bool> && result.value;
    emit(
      state.copyWith(
        loadingOlder: false,
        reachedStart: state.reachedStart || reached,
      ),
    );
  }

  Future<bool> send(String text) async {
    final conversation = _conversation;
    if (text.trim().isEmpty || conversation == null) return false;
    final result = await conversation.send(text);
    return result is Ok;
  }

  Future<bool> retry(String messageId) async =>
      await _conversation?.retry(messageId) is Ok;

  Future<bool> cancel(String messageId) async =>
      await _conversation?.cancel(messageId) is Ok;

  void toggleThread(String rootEventId) {
    final expanded = {...state.expandedThreads};
    if (expanded.remove(rootEventId)) {
      _threads.remove(rootEventId)?.close();
    } else {
      expanded.add(rootEventId);
      _threads[rootEventId] = ThreadViewModel(() => openThread(rootEventId))
        ..open();
    }
    emit(state.copyWith(expandedThreads: expanded));
  }

  ThreadViewModel? thread(String rootEventId) => _threads[rootEventId];

  Future<Result<Conversation>> openThread(String rootEventId) async =>
      await _conversation?.openThread(rootEventId) ??
      const Result.error(ConversationFailure(ConversationFailureType.unknown));

  void _onSnapshot(ConversationSnapshot snapshot) {
    if (_closing || isClosed) return;
    emit(
      state.copyWith(
        status: ConversationStatus.ready,
        items: snapshot.items,
        reachedStart: snapshot.reachedStart,
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
    await Future.wait(_threads.values.map((thread) => thread.close()));
    _conversation?.dispose();
    return super.close();
  }
}
