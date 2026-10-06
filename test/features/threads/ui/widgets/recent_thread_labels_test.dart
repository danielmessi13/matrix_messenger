import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/threads/domain/models/recent_thread.dart';
import 'package:matrix_messenger/features/threads/ui/widgets/recent_thread_labels.dart';

import '../../../../../testing/models/recent_thread.dart';

void main() {
  test('raiz mostra o primeiro nome do autor, ou Você', () {
    expect(threadRootPreview(kTeamThread.root), 'Carla: Quem revisa o deck?');
    expect(threadRootPreview(kDirectThread.root), 'Você: Viu o contrato?');
  });

  test('raiz cifrada mostra Mensagem criptografada', () {
    final root = LatestMessage(
      senderName: 'Bob',
      isOwn: false,
      kind: LatestMessageKind.encrypted,
      timestamp: DateTime(2026),
    );
    expect(threadRootPreview(root), 'Bob: Mensagem criptografada');
  });

  test('atividade: contagem, autor e horário da última resposta', () {
    expect(
      threadActivityLabel(kTeamThread),
      '3 respostas · última de Diego às 11:05',
    );
  });

  test('sem resposta: Nenhuma resposta ainda', () {
    expect(threadActivityLabel(kDirectThread), 'Nenhuma resposta ainda');
    expect(threadLatestPreview(kDirectThread), '');
  });

  test('última resposta em uma linha, sem quebras', () {
    final thread = RecentThread(
      roomId: '!a:b.c',
      rootEventId: r'$r',
      root: kTeamThread.root,
      latestReply: LatestMessage(
        senderName: 'Ana',
        isOwn: true,
        kind: LatestMessageKind.text,
        body: 'linha 1\nlinha 2',
        timestamp: DateTime(2026, 1, 1, 8, 3),
      ),
      replyCount: 1,
      activity: DateTime(2026, 1, 1, 8, 3),
    );
    expect(threadLatestPreview(thread), 'linha 1 linha 2');
    expect(threadActivityLabel(thread), '1 resposta · última sua às 08:03');
  });
}
