import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix_messenger/features/conversation/ui/widgets/markdown_text.dart';

void main() {
  const style = TextStyle(fontSize: 20);
  const code = TextStyle(fontFamily: 'monospace');

  List<TextSpan> leaves(TextSpan span) => [
    if (span.text != null) span,
    for (final child in span.children ?? const <InlineSpan>[])
      if (child is TextSpan) ...leaves(child),
  ];

  TextSpan find(TextSpan root, String text) =>
      leaves(root).firstWhere((span) => span.text == text);

  test('texto sem marcação fica igual', () {
    expect(
      markdownSpan(
        'oi, tudo bem?',
        style: style,
        codeStyle: code,
      ).toPlainText(),
      'oi, tudo bem?',
    );
  });

  test('negrito, itálico, riscado e código', () {
    final span = markdownSpan(
      '**forte** _leve_ ~~fora~~ `x = 1`',
      style: style,
      codeStyle: code,
    );

    expect(span.toPlainText(), 'forte leve fora x = 1');
    expect(find(span, 'forte').style?.fontWeight, FontWeight.w600);
    expect(find(span, 'leve').style?.fontStyle, FontStyle.italic);
    expect(find(span, 'fora').style?.decoration, TextDecoration.lineThrough);
    expect(find(span, 'x = 1').style?.fontFamily, 'monospace');
  });

  test('aninhamento acumula estilos', () {
    final span = markdownSpan('**_ambos_**', style: style, codeStyle: code);
    final leaf = find(span, 'ambos');

    expect(leaf.style?.fontWeight, FontWeight.w600);
    expect(leaf.style?.fontStyle, FontStyle.italic);
  });

  test('listas e parágrafos viram linhas', () {
    final span = markdownSpan(
      'itens:\n\n- um\n- dois',
      style: style,
      codeStyle: code,
    );

    expect(span.toPlainText(), 'itens:\n• um\n• dois');
  });

  test('caracteres especiais não viram entidades', () {
    expect(
      markdownSpan('a & b < c', style: style, codeStyle: code).toPlainText(),
      'a & b < c',
    );
  });

  String plain(String source) =>
      markdownSpan(source, style: style, codeStyle: code).toPlainText();

  test('lista aninhada recua dois espaços por nível', () {
    expect(plain('- a\n  - b\n- c'), '• a\n  • b\n• c');
  });

  test('item de lista frouxa com mais de um parágrafo', () {
    expect(plain('- a\n\n  b\n- c'), '• a\n  b\n• c');
  });

  test('citação separa parágrafos sem o marcador', () {
    expect(plain('> um\n>\n> dois'), 'um\ndois');
  });

  test('tabela vira uma linha por linha com células separadas', () {
    expect(plain('| a | b |\n|---|---|\n| 1 | 2 |'), 'a | b\n1 | 2');
  });

  test('cabeçalho em negrito', () {
    final span = markdownSpan('# Título', style: style, codeStyle: code);

    expect(span.toPlainText(), 'Título');
    expect(find(span, 'Título').style?.fontWeight, FontWeight.w600);
  });

  test('bloco de código cercado', () {
    final span = markdownSpan(
      '```\nx = 1\ny = 2\n```',
      style: style,
      codeStyle: code,
    );

    expect(span.toPlainText(), 'x = 1\ny = 2');
    expect(find(span, 'x = 1\ny = 2').style?.fontFamily, 'monospace');
  });

  test('lista ordenada respeita o início', () {
    expect(plain('3. a\n4. b'), '3. a\n4. b');
  });

  test('link mostra a URL', () {
    expect(
      plain('[clique aqui](https://exemplo.com)'),
      'clique aqui (https://exemplo.com)',
    );
    expect(plain('<https://exemplo.com>'), 'https://exemplo.com');
  });

  test('quebra de linha do Windows não deixa \\r', () {
    expect(plain('a\r\nb'), isNot(contains('\r')));
    expect(plain('a\r\n\r\nb'), 'a\nb');
  });

  test('mesmo texto com outro estilo usa o estilo novo', () {
    const other = TextStyle(fontSize: 14);
    markdownSpan('**repetido**', style: style, codeStyle: code);
    final span = markdownSpan('**repetido**', style: other, codeStyle: code);

    expect(find(span, 'repetido').style?.fontSize, 14);
    expect(find(span, 'repetido').style?.fontWeight, FontWeight.w600);
  });

  test('textos além do limite do cache continuam corretos', () {
    for (var i = 0; i < 600; i++) {
      markdownSpan('_msg ${i}_', style: style, codeStyle: code);
    }

    final first = markdownSpan('_msg 0_', style: style, codeStyle: code);
    final last = markdownSpan('_msg 599_', style: style, codeStyle: code);

    expect(first.toPlainText(), 'msg 0');
    expect(find(first, 'msg 0').style?.fontStyle, FontStyle.italic);
    expect(last.toPlainText(), 'msg 599');
  });
}
