import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

TextSpan markdownSpan(
  String source, {
  required TextStyle style,
  required TextStyle codeStyle,
}) {
  final nodes = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  ).parseLines(source.replaceAll('\r\n', '\n').split('\n'));
  final lines = _lines(nodes, style, codeStyle);
  return TextSpan(style: style, children: _joinLines(lines));
}

class MarkdownText extends StatelessWidget {
  const MarkdownText({
    super.key,
    required this.source,
    required this.style,
    required this.codeStyle,
  });

  final String source;

  final TextStyle style;

  final TextStyle codeStyle;

  @override
  Widget build(BuildContext context) =>
      Text.rich(markdownSpan(source, style: style, codeStyle: codeStyle));
}

const _inlineTags = {
  'strong', 'em', 'del', 'code', 'a', 'br', 'img', 'span', 'sup', 'sub', 'input',
};

List<List<InlineSpan>> _lines(List<md.Node> nodes, TextStyle style, TextStyle code) {
  final lines = <List<InlineSpan>>[];
  var pending = <InlineSpan>[];
  void flush() {
    final blank = pending.every((s) => s is TextSpan && (s.text ?? '').trim().isEmpty);
    if (!blank) lines.add(pending);
    pending = [];
  }

  for (final node in nodes) {
    if (node is! md.Element || _inlineTags.contains(node.tag)) {
      pending.addAll(_inlineSpans(node, style, code));
      continue;
    }
    flush();
    lines.addAll(_blockLines(node, style, code));
  }
  flush();
  return lines;
}

List<List<InlineSpan>> _blockLines(md.Element node, TextStyle style, TextStyle code) {
  final children = node.children ?? const <md.Node>[];
  switch (node.tag) {
    case 'ul' || 'ol':
      final start = int.tryParse(node.attributes['start'] ?? '') ?? 1;
      return [
        for (final (index, item) in children.indexed)
          ..._itemLines(
            node.tag == 'ul' ? '• ' : '${start + index}. ',
            item is md.Element ? _lines(item.children ?? const [], style, code) : const [],
          ),
      ];
    case 'tr':
      return [
        [
          for (final (index, cell) in children.indexed) ...[
            if (index > 0) TextSpan(text: ' | ', style: style),
            ..._inlineSpans(cell, style, code),
          ],
        ],
      ];
    case 'pre':
      final text = node.textContent.replaceFirst(RegExp(r'\n+$'), '');
      return [
        [TextSpan(text: text, style: style.merge(code))],
      ];
    case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
      return _lines(children, style.copyWith(fontWeight: FontWeight.w600), code);
    default:
      return _lines(children, style, code);
  }
}

List<List<InlineSpan>> _itemLines(String marker, List<List<InlineSpan>> lines) {
  if (lines.isEmpty) return [[TextSpan(text: marker.trimRight())]];
  return [
    for (final (index, line) in lines.indexed)
      [TextSpan(text: index == 0 ? marker : '  '), ...line],
  ];
}

List<InlineSpan> _inlineSpans(md.Node node, TextStyle style, TextStyle code) {
  if (node is md.Text) return [TextSpan(text: node.text, style: style)];
  if (node is! md.Element) return [TextSpan(text: node.textContent, style: style)];
  if (node.tag == 'br') return [const TextSpan(text: '\n')];
  final nested = switch (node.tag) {
    'strong' => style.copyWith(fontWeight: FontWeight.w600),
    'em' => style.copyWith(fontStyle: FontStyle.italic),
    'del' => style.copyWith(decoration: TextDecoration.lineThrough),
    'code' => style.merge(code),
    _ => style,
  };
  final spans = [
    for (final child in node.children ?? const <md.Node>[])
      ..._inlineSpans(child, nested, code),
  ];
  final href = node.attributes['href'];
  if (node.tag == 'a' && href != null) {
    final text = node.textContent;
    if (text != href && 'http://$text' != href) {
      spans.add(TextSpan(text: ' ($href)', style: style));
    }
  }
  return spans;
}

List<InlineSpan> _joinLines(List<List<InlineSpan>> lines) => [
  for (final (index, line) in lines.indexed) ...[
    if (index > 0) const TextSpan(text: '\n'),
    ...line,
  ],
];
