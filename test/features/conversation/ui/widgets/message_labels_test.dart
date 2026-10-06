import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/conversation/domain/models/timeline_item.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/message_labels.dart';

void main() {
  final now = DateTime(2026, 10, 4, 12);

  test('divisor de data', () {
    expect(formatDayDivider(DateTime(2026, 10, 4), now), 'Hoje, 4 de outubro');
    expect(formatDayDivider(DateTime(2026, 10, 3), now), 'Ontem, 3 de outubro');
    expect(formatDayDivider(DateTime(2026, 9, 28), now), '28 de setembro');
    expect(
      formatDayDivider(DateTime(2025, 12, 31), now),
      '31 de dezembro de 2025',
    );
    expect(
      formatDayDivider(DateTime(2025, 12, 31), DateTime(2026, 1, 1, 9)),
      'Ontem, 31 de dezembro',
    );
  });

  test('horário da mensagem', () {
    expect(formatMessageTime(DateTime(2026, 10, 4, 9, 5)), '09:05');
  });

  test('lida por sem leitores', () {
    expect(readByLabel([]), '');
  });

  test('lida por', () {
    expect(readByLabel(['Carla Mendes']), '✓✓ Lida por Carla');
    expect(
      readByLabel(['Carla Mendes', 'Diego Alves']),
      '✓✓ Lida por Carla e Diego',
    );
    expect(
      readByLabel(['Carla', 'Diego', 'Ana']),
      '✓✓ Lida por Carla, Diego e Ana',
    );
    expect(
      readByLabel(['Carla', 'Diego', 'Ana', 'Bruno', 'Elisa']),
      '✓✓ Lida por Carla, Diego, Ana e mais 2',
    );
  });

  test('resumo da thread', () {
    expect(repliesLabel(1), '1 resposta');
    expect(repliesLabel(4), '4 respostas');
    expect(
      threadSummaryLabel(
        ThreadSummary(
          rootEventId: '\$r',
          replies: 4,
          latestSender: 'Ana Ribeiro',
          latestAt: DateTime(2026, 10, 4, 10, 20),
        ),
      ),
      'última de Ana às 10:20',
    );
    expect(
      threadSummaryLabel(
        ThreadSummary(
          rootEventId: '\$r',
          replies: 1,
          latestAt: DateTime(2026, 10, 4, 10, 20),
        ),
      ),
      'última às 10:20',
    );
    expect(
      threadSummaryLabel(const ThreadSummary(rootEventId: '\$r', replies: 1)),
      '',
    );
  });

  final diego = MessageItem(
    id: 'a',
    senderId: '@diego:b.c',
    senderName: 'Diego Alves',
    isOwn: false,
    timestamp: DateTime(2026, 10, 4),
    kind: MessageKind.text,
    body: 'oi',
  );
  final mine = MessageItem(
    id: 'b',
    senderId: '@alice:b.c',
    senderName: 'Alice',
    isOwn: true,
    timestamp: DateTime(2026, 10, 4),
    kind: MessageKind.image,
  );

  test('barra de resposta', () {
    expect(replyBarLabel(diego), 'Respondendo a Diego Alves');
    expect(replyBarLabel(mine), 'Respondendo a você mesmo');
    expect(messageExcerpt(diego), 'oi');
    expect(messageExcerpt(mine), 'Imagem');
  });

  test('placeholder do composer', () {
    expect(composerHint(roomTitle: '#geral'), 'Escrever para #geral…');
    expect(
      composerHint(roomTitle: '#geral', replyTo: diego),
      'Responder a Diego…',
    );
    expect(
      composerHint(roomTitle: '#geral', replyTo: mine),
      'Responder a você mesmo…',
    );
    expect(
      composerHint(roomTitle: '#geral', inThread: true),
      'Responder na thread…',
    );
    expect(
      composerHint(roomTitle: '#geral', replyTo: diego, inThread: true),
      'Responder a Diego na thread…',
    );
  });

  test('painel da thread', () {
    expect(threadTitle(diego), 'Thread de Diego');
    expect(threadTitle(mine), 'Sua thread');
    expect(threadCountLabel(0), 'Nenhuma resposta ainda. Escreva a primeira.');
    expect(threadCountLabel(1), '1 resposta');
    expect(newRepliesLabel(1), '1 nova resposta');
    expect(newRepliesLabel(3), '3 novas respostas');
    expect(repliedToYouLabel('Diego Alves'), 'Diego Alves respondeu a você');
  });

  test('texto da citação em cada estado', () {
    expect(
      replyQuoteLabel(
        const ReplyPreview(eventId: '\$x', state: ReplyState.loading),
      ),
      'Carregando mensagem…',
    );
    expect(
      replyQuoteLabel(
        const ReplyPreview(eventId: '\$x', state: ReplyState.unavailable),
      ),
      'Mensagem original indisponível',
    );
    expect(
      replyQuoteLabel(
        const ReplyPreview(
          eventId: '\$x',
          state: ReplyState.ready,
          kind: MessageKind.text,
          body: 'oi',
        ),
      ),
      'oi',
    );
    expect(
      replyQuoteLabel(
        const ReplyPreview(
          eventId: '\$x',
          state: ReplyState.ready,
          kind: MessageKind.image,
        ),
      ),
      'Imagem',
    );
  });

  test('textos dos tipos sem texto', () {
    expect(kindPlaceholder(MessageKind.text), isNull);
    expect(kindPlaceholder(MessageKind.notice), isNull);
    expect(kindPlaceholder(MessageKind.emote), isNull);
    expect(kindPlaceholder(MessageKind.image), 'Imagem');
    expect(kindPlaceholder(MessageKind.file), 'Arquivo');
    expect(
      kindPlaceholder(MessageKind.encrypted),
      'Mensagem criptografada — não foi possível descriptografar neste dispositivo',
    );
    expect(kindPlaceholder(MessageKind.redacted), 'Mensagem apagada');
    expect(
      kindPlaceholder(MessageKind.other),
      'Mensagem de um tipo não suportado',
    );
  });

  test('quem está digitando', () {
    expect(typingLabel([]), '');
    expect(typingLabel(['Bob']), 'Bob está digitando…');
    expect(typingLabel(['Bob', 'Ana']), 'Bob e Ana estão digitando…');
    expect(
      typingLabel(['Bob', 'Ana', 'Carlos']),
      'Bob, Ana e Carlos estão digitando…',
    );
    expect(
      typingLabel(['Bob', 'Ana', 'Carlos', 'Diego']),
      'Várias pessoas estão digitando…',
    );
    expect(typingLabel(['Diego Alves']), 'Diego está digitando…');
  });
}
