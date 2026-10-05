import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/domain/models/room.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/widgets/room_labels.dart';

import '../../../../../../testing/models/room.dart';

void main() {
  group('formatRoomTime', () {
    final now = DateTime(2026, 10, 4, 12); // domingo

    test('hoje mostra a hora, inclusive logo depois da meia-noite', () {
      expect(formatRoomTime(DateTime(2026, 10, 4, 10, 42), now), '10:42');
      expect(formatRoomTime(DateTime(2026, 10, 4, 0, 30), now), '00:30');
    });

    test('ontem, inclusive 23:50', () {
      expect(formatRoomTime(DateTime(2026, 10, 3, 23, 50), now), 'Ontem');
    });

    test('até 6 dias atrás mostra o dia da semana', () {
      expect(formatRoomTime(DateTime(2026, 9, 29, 9), now), 'Ter');
      expect(formatRoomTime(DateTime(2026, 9, 28, 9), now), 'Seg');
    });

    test('7 dias ou mais mostra a data', () {
      expect(formatRoomTime(DateTime(2026, 9, 27, 9), now), '27/09');
    });

    test('a troca de horário de verão não encurta um dia', () {
      // Em fusos com horário de verão, a meia-noite local pode ter 23 h.
      expect(
        formatRoomTime(DateTime(2026, 3, 28, 22), DateTime(2026, 3, 29, 1)),
        'Ontem',
      );
    });
  });

  test('nome vazio vira "Sala vazia"', () {
    expect(roomName(const Room(id: '!x:b.c', name: '')), 'Sala vazia');
  });

  test('salas levam # e DMs não', () {
    expect(roomListLabel(kTeamRoom), '# lançamento-q4');
    expect(roomTitle(kTeamRoom), '#lançamento-q4');
    expect(roomListLabel(kDirectRoom), 'Ana Ribeiro');
    expect(roomInitials(kTeamRoom), '#');
    expect(roomInitials(kDirectRoom), 'AR');
  });

  group('latestPreview', () {
    LatestMessage message(
      LatestMessageKind kind, {
      String? body,
      bool own = false,
    }) => LatestMessage(
      senderName: 'Carla Mendes',
      isOwn: own,
      kind: kind,
      body: body,
      timestamp: kNow,
    );

    test('sala: primeiro nome do autor', () {
      expect(latestPreview(kTeamRoom), 'Carla: Subi a versão final do deck.');
    });

    test('DM: só o texto', () {
      expect(latestPreview(kDirectRoom), 'Valeu! É o #482.');
    });

    test('mensagem própria: "Você:"', () {
      expect(latestPreview(kQuietRoom), 'Você: Ótimo, vou atualizar o deck.');
    });

    test('tipos sem texto', () {
      Room room(LatestMessage latest) =>
          Room(id: '!r:b.c', name: 'r', latest: latest);
      expect(
        latestPreview(room(message(LatestMessageKind.image))),
        'Carla: Imagem',
      );
      expect(
        latestPreview(room(message(LatestMessageKind.file))),
        'Carla: Arquivo',
      );
      expect(
        latestPreview(room(message(LatestMessageKind.encrypted))),
        'Carla: Mensagem criptografada',
      );
      expect(
        latestPreview(room(message(LatestMessageKind.other))),
        'Carla: Mensagem',
      );
    });

    test('quebras de linha viram espaço', () {
      final room = Room(
        id: '!r:b.c',
        name: 'r',
        isDirect: true,
        latest: message(LatestMessageKind.text, body: 'linha 1\n\nlinha 2'),
      );
      expect(latestPreview(room), 'linha 1 linha 2');
    });

    test('convite sem mensagem', () {
      expect(latestPreview(kInviteRoom), 'Convite para entrar');
      expect(latestPreview(const Room(id: '!v:b.c', name: 'v')), '');
    });
  });

  test('não lidas no singular e no plural', () {
    expect(unreadLabel(1), '1 nova');
    expect(unreadLabel(4), '4 novas');
  });

  test('rótulo do cabeçalho', () {
    expect(roomMetaLabel(kTeamRoom), 'SALA · 12 MEMBROS');
    expect(
      roomMetaLabel(const Room(id: '!s:b.c', name: 's', memberCount: 1)),
      'SALA · 1 MEMBRO',
    );
    expect(roomMetaLabel(kDirectRoom), 'MENSAGEM DIRETA');
    expect(roomMetaLabel(kInviteRoom), 'CONVITE');
  });
}
