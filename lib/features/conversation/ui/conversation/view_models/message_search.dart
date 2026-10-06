import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/models/timeline_item.dart';

const searchPages = 3;

// As páginas novas chegam pelo stream depois do loadOlder, com a janela de 100 ms da ponte.
const kSnapshotWait = Duration(seconds: 1);

final class FocusRequest extends Equatable {
  const FocusRequest(this.messageId, this.seq);

  // Nulo quando a mensagem não está no histórico carregado.
  final String? messageId;

  // Pedir a mesma mensagem duas vezes precisa rolar de novo.
  final int seq;

  @override
  List<Object?> get props => [messageId, seq];
}

Future<String?> searchMessage<S>(
  Cubit<S> cubit, {
  required String eventId,
  required List<TimelineItem> Function(S state) items,
  required bool Function(S state) reachedStart,
  required Future<void> Function() loadOlder,
}) async {
  for (var page = 0; ; page++) {
    final state = cubit.state;
    final found = items(state)
        .whereType<MessageItem>()
        .where((message) => message.eventId == eventId)
        .firstOrNull;
    if (found != null) return found.id;
    if (reachedStart(state) || page == searchPages || cubit.isClosed) {
      return null;
    }
    final before = items(state);
    final next = cubit.stream
        .firstWhere((s) => !identical(items(s), before))
        .timeout(kSnapshotWait, onTimeout: () => cubit.state)
        .then((s) => s, onError: (Object _) => cubit.state);
    await loadOlder();
    await next;
  }
}
