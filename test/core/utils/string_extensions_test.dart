import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/core/utils/string_extensions.dart';

void main() {
  group('foldedForSearch', () {
    test('ignora maiúsculas e acentos', () {
      expect('LANÇAMENTO-Q4'.foldedForSearch, 'lancamento-q4');
      expect('Ação Única à Vista'.foldedForSearch, 'acao unica a vista');
      expect('Ñandú Über'.foldedForSearch, 'nandu uber');
    });

    test('remove acentos fora do português', () {
      expect('Łukasz Søren'.foldedForSearch, 'lukasz soren');
    });
  });

  group('initials', () {
    test('duas palavras viram as duas iniciais', () {
      expect('Carla Mendes'.initials, 'CM');
      expect('squad.pagamentos'.initials, 'SP');
    });

    test('uma palavra vira as duas primeiras letras', () {
      expect('engenharia'.initials, 'EN');
      expect('#geral'.initials, 'GE');
    });

    test('vazio vira interrogação', () {
      expect(''.initials, '?');
      expect('  '.initials, '?');
    });

    test('iniciais do usuário vêm da parte local do Matrix ID', () {
      expect('@alice:matrix.org'.userInitials, 'AL');
      expect('@daniel.messias:matrix.org'.userInitials, 'DM');
    });
  });
}
