import '../../domain/models/timeline_item.dart';

const _months = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

String formatDayDivider(DateTime day, DateTime now) {
  // Datas em UTC para a troca de horário de verão não encurtar um dia.
  final target = DateTime.utc(day.year, day.month, day.day);
  final today = DateTime.utc(now.year, now.month, now.day);
  final days = today.difference(target).inDays;
  final date = '${day.day} de ${_months[day.month - 1]}';
  if (days == 0) return 'Hoje, $date';
  if (days == 1) return 'Ontem, $date';
  return day.year == now.year ? date : '$date de ${day.year}';
}

String formatMessageTime(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _firstName(String name) => name.trim().split(RegExp(r'\s+')).first;

String readByLabel(List<String> names) {
  if (names.isEmpty) return '';
  final first = names.map(_firstName).toList();
  final shown = first.length > 3 ? first.take(3).toList() : first;
  final extra = first.length - shown.length;
  final String joined;
  if (extra > 0) {
    joined = '${shown.join(', ')} e mais $extra';
  } else if (shown.length == 1) {
    joined = shown.first;
  } else {
    joined = '${shown.take(shown.length - 1).join(', ')} e ${shown.last}';
  }
  return '✓✓ Lida por $joined';
}

String typingLabel(List<String> names) {
  final first = names.map(_firstName).toList();
  return switch (first) {
    [] => '',
    [final one] => '$one está digitando…',
    [final a, final b] => '$a e $b estão digitando…',
    [final a, final b, final c] => '$a, $b e $c estão digitando…',
    _ => 'Várias pessoas estão digitando…',
  };
}

String repliesLabel(int count) =>
    '$count ${count == 1 ? 'resposta' : 'respostas'}';

String replyBarLabel(MessageItem target) => target.isOwn
    ? 'Respondendo a você mesmo'
    : 'Respondendo a ${target.senderName}';

String messageExcerpt(MessageItem message) =>
    message.body ?? kindPlaceholder(message.kind) ?? '';

String composerHint({
  required String roomTitle,
  MessageItem? replyTo,
  bool inThread = false,
}) {
  if (replyTo != null) {
    final who = replyTo.isOwn ? 'você mesmo' : _firstName(replyTo.senderName);
    return 'Responder a $who${inThread ? ' na thread' : ''}…';
  }
  return inThread ? 'Responder na thread…' : 'Escrever para $roomTitle…';
}

String threadTitle(MessageItem root) =>
    root.isOwn ? 'Sua thread' : 'Thread de ${_firstName(root.senderName)}';

String threadCountLabel(int replies) => replies == 0
    ? 'Nenhuma resposta ainda. Escreva a primeira.'
    : repliesLabel(replies);

String newRepliesLabel(int count) =>
    count == 1 ? '1 nova resposta' : '$count novas respostas';

String repliedToYouLabel(String senderName) => '$senderName respondeu a você';

String threadSummaryLabel(ThreadSummary thread) {
  final at = thread.latestAt;
  if (at == null) return '';
  final sender = thread.latestSender;
  final who = sender == null ? '' : ' de ${_firstName(sender)}';
  return 'última$who às ${formatMessageTime(at)}';
}

String replyQuoteLabel(ReplyPreview reply) => switch (reply.state) {
  ReplyState.loading => 'Carregando mensagem…',
  ReplyState.unavailable => 'Mensagem original indisponível',
  ReplyState.ready =>
    reply.body ?? kindPlaceholder(reply.kind ?? MessageKind.other) ?? '',
};

String? kindPlaceholder(MessageKind kind) => switch (kind) {
  MessageKind.text || MessageKind.notice || MessageKind.emote => null,
  MessageKind.image => 'Imagem',
  MessageKind.file => 'Arquivo',
  MessageKind.encrypted => 'Mensagem criptografada — não foi possível descriptografar neste dispositivo',
  MessageKind.redacted => 'Mensagem apagada',
  MessageKind.other => 'Mensagem de um tipo não suportado',
};

String reactionTooltip(MessageReaction reaction) {
  final names = [...reaction.senderNames, if (reaction.reactedByMe) 'você'];
  if (names.length > 10) {
    return '${names[0]}, ${names[1]} e mais ${names.length - 2}';
  }
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';
}
