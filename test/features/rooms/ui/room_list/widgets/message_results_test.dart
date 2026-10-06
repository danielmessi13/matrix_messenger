import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/rooms/ui/room_list/widgets/message_results.dart';

void main() {
  String marked(Snippet snippet) {
    final buffer = StringBuffer();
    var cursor = 0;
    for (final (start, end) in snippet.matches) {
      buffer
        ..write(snippet.text.substring(cursor, start))
        ..write('[${snippet.text.substring(start, end)}]');
      cursor = end;
    }
    return (buffer..write(snippet.text.substring(cursor))).toString();
  }

  test('destaca cada palavra do termo, sem acento nem caixa', () {
    expect(
      marked(searchSnippet('Reunião de  DEPLOY\namanhã', 'reuniao deploy')),
      '[Reunião] de [DEPLOY] amanhã',
    );
  });

  test('ocorrências sobrepostas viram um destaque só', () {
    expect(marked(searchSnippet('deployment', 'deploy ploym')), '[deploym]ent');
  });

  test('termo no fim de um texto longo corta o começo numa palavra', () {
    final body = '${List.filled(20, 'palavra').join(' ')} o deploy saiu';
    final snippet = marked(searchSnippet(body, 'deploy'));

    expect(snippet, startsWith('…palavra'));
    expect(snippet, endsWith('o [deploy] saiu'));
    expect(snippet.length, lessThan(body.length));
  });

  test('sem ocorrência devolve o texto inteiro sem destaque', () {
    final snippet = searchSnippet('nada aqui', 'deploy');
    expect(snippet.text, 'nada aqui');
    expect(snippet.matches, isEmpty);
  });
}
