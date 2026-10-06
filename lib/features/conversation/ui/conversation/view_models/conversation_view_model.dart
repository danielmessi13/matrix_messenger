import 'dart:async';
import 'dart:developer';
import 'dart:math' show max;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/utils/result.dart';
import '../../../data/repositories/conversation_repository.dart';
import '../../../domain/models/conversation.dart';
import '../../../domain/models/conversation_failure.dart';
import '../../../domain/models/timeline_item.dart';
import '../../thread/view_models/thread_view_model.dart';
import 'conversation_state.dart';
import 'message_search.dart';

// Do disco, o SDK entrega blocos de até 128 eventos de uma vez; a tela revela 20 mensagens por vez.
const _windowStep = 20;

class ConversationViewModel extends Cubit<ConversationState> {
  ConversationViewModel(this._repository, this.roomId)
    : super(const ConversationState());

  final ConversationRepository _repository;

  final String roomId;

  Conversation? _conversation;

  StreamSubscription<ConversationSnapshot>? _updates;

  StreamSubscription<List<String>>? _typing;

  // Último aviso enviado, para não repetir a cada tecla.
  bool _typingSent = false;

  String? _latestMessageId;

  List<TimelineItem> _loaded = const [];

  // A janela vai desta mensagem até o fim, então mensagem nova embaixo não tira ninguém de cima.
  String? _oldestVisibleId;

  bool _sdkReachedStart = false;

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
    _loaded = const [];
    _oldestVisibleId = null;
    _sdkReachedStart = false;
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
        _typing = value.typing.listen(
          _onTyping,
          onError: (Object error) =>
              log('Digitação da conversa', name: 'conversation', error: error),
        );
      case Error(:final error):
        log('Falha ao abrir a conversa', name: 'conversation', error: error);
        emit(state.copyWith(status: ConversationStatus.failed));
    }
  }

  // True quando a busca rodou sem chegar ao início: uma página só de eventos ocultos não muda o estado, então quem chamou reavalia.
  Future<bool> loadOlder() async {
    if (state.status == ConversationStatus.ready && state.hiddenOlder > 0) {
      _reveal();
      return true;
    }
    return _fetchOlder();
  }

  Future<bool> _fetchOlder() async {
    final conversation = _conversation;
    if (conversation == null ||
        _loadingOlder ||
        state.paginating ||
        _sdkReachedStart ||
        state.status != ConversationStatus.ready) {
      return false;
    }
    _loadingOlder = true;
    try {
      final result = await conversation.loadOlder();
      if (_closing || isClosed) return false;
      switch (result) {
        case Ok(:final value):
          _sdkReachedStart = _sdkReachedStart || value;
          _emitWindow(state.copyWith(olderFailed: false));
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
    unawaited(_setTyping(false));
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

  // Como o texto, a imagem responde à mensagem marcada; o eco local chega pelo snapshot.
  Future<void> sendImage(String path) async {
    final conversation = _conversation;
    if (conversation == null || state.imageSend == ImageSendStatus.sending) {
      return;
    }
    emit(state.copyWith(imageSend: ImageSendStatus.sending));
    final target = state.replyTo;
    final result = await conversation.sendImage(
      path,
      inReplyTo: target?.eventId,
    );
    if (_closing || isClosed) return;
    switch (result) {
      case Ok():
        emit(
          state.replyTo == target
              ? state.copyWith(imageSend: ImageSendStatus.idle, replyTo: null)
              : state.copyWith(imageSend: ImageSendStatus.idle),
        );
      case Error(:final error):
        log('Falha ao enviar a imagem', name: 'conversation', error: error);
        emit(
          state.copyWith(
            imageSend:
                error is ConversationFailure &&
                    error.type == ConversationFailureType.invalidImage
                ? ImageSendStatus.invalid
                : ImageSendStatus.failed,
          ),
        );
    }
  }

  Future<bool> retry(String messageId) async =>
      await _conversation?.retry(messageId) is Ok;

  Future<bool> cancel(String messageId) async =>
      await _conversation?.cancel(messageId) is Ok;

  void onDraftChanged(String text) =>
      unawaited(_setTyping(text.trim().isNotEmpty));

  Future<void> _setTyping(bool typing) async {
    final conversation = _conversation;
    if (conversation == null || typing == _typingSent) return;
    _typingSent = typing;
    await conversation.setTyping(typing);
  }

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
    final before = _loaded;
    await _fetchOlder();
    if (_sdkReachedStart) return;
    await _untilIdle((_) => !identical(_loaded, before));
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
      items: (_) => _loaded,
      reachedStart: (_) => _sdkReachedStart,
      loadOlder: _loadOlderSettled,
    );
    if (_closing || isClosed) return;
    if (id != null) _revealUpTo(id);
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
    _loaded = snapshot.items;
    _sdkReachedStart = snapshot.reachedStart;
    _emitWindow(
      state.copyWith(
        status: ConversationStatus.ready,
        paginating: snapshot.paginating,
      ),
    );
    final latest = snapshot.items.whereType<MessageItem>().lastOrNull;
    if (latest != null && latest.id != _latestMessageId && !latest.isOwn) {
      _conversation?.markAsRead();
    }
    _latestMessageId = latest?.id;
  }

  void _reveal() {
    final messages = _loaded.whereType<MessageItem>().toList();
    final top = messages.indexWhere((m) => m.id == _oldestVisibleId);
    _oldestVisibleId = messages[max(0, top - _windowStep)].id;
    _emitWindow(state);
  }

  void _revealUpTo(String messageId) {
    final index = _loaded.indexWhere(
      (item) => item is MessageItem && item.id == messageId,
    );
    if (index < 0 || index >= state.hiddenOlder) return;
    _oldestVisibleId = messageId;
    _emitWindow(state);
  }

  void _emitWindow(ConversationState base) {
    final start = _firstVisibleIndex();
    emit(
      base.copyWith(
        items: start == 0 ? _loaded : _loaded.sublist(start),
        hiddenOlder: start,
        reachedStart: _sdkReachedStart && start == 0,
      ),
    );
  }

  int _firstVisibleIndex() {
    final messages = _loaded.whereType<MessageItem>().toList();
    if (messages.isEmpty) return 0;
    final anchor = _oldestVisibleId ??=
        messages[max(0, messages.length - _windowStep)].id;
    if (anchor == messages.first.id) return 0;
    final anchorIndex = _loaded.indexWhere(
      (item) => item is MessageItem && item.id == anchor,
    );
    if (anchorIndex < 0) {
      _oldestVisibleId = messages.first.id;
      return 0;
    }
    final dividerAbove = _loaded[anchorIndex - 1] is DateDividerItem;
    return dividerAbove ? anchorIndex - 1 : anchorIndex;
  }

  void _onTyping(List<String> names) {
    if (_closing || isClosed) return;
    emit(state.copyWith(typing: names));
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
    _typing?.cancel();
    _typing = null;
    _typingSent = false;
    _conversation?.dispose();
    _conversation = null;
    emit(state.copyWith(status: ConversationStatus.failed));
  }

  @override
  Future<void> close() async {
    _closing = true;
    await _setTyping(false);
    await _updates?.cancel();
    await _typing?.cancel();
    await _thread?.close();
    _conversation?.dispose();
    return super.close();
  }
}
