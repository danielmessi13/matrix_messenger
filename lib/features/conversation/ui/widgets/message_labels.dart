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

String repliesLabel(int count) =>
    '$count ${count == 1 ? 'resposta' : 'respostas'}';

String unreadRepliesLabel(int count) => count == 1 ? '1 nova' : '$count novas';

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
