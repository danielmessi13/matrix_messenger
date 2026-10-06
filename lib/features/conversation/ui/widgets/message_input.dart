import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';
import '../../../rooms/domain/models/room.dart';
import '../../../rooms/ui/room_list/widgets/room_labels.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.room,
    required this.onSend,
    this.enabled = true,
  });

  final Room room;

  final bool enabled;

  final Future<bool> Function(String text) onSend;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();

  final _focus = FocusNode(debugLabel: 'message_field');

  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = _onKey;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter ||
        event is KeyUpEvent ||
        HardwareKeyboard.instance.isShiftPressed ||
        _controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    // O repeat é consumido para o Enter segurado não inserir quebras de linha.
    if (event is KeyDownEvent) _send();
    return KeyEventResult.handled;
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (!widget.enabled || _sending || text.trim().isEmpty) return;
    setState(() => _sending = true);
    bool sent;
    try {
      sent = await widget.onSend(text);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (!mounted) return;
    if (sent) {
      if (_controller.text == text) _controller.clear();
      _focus.requestFocus();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar.')),
      );
    }
  }

  void _wrap(String marker) {
    final value = _controller.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final selected = selection.textInside(value.text);
    final text = value.text.replaceRange(
      selection.start,
      selection.end,
      '$marker$selected$marker',
    );
    final cursor = selected.isEmpty
        ? selection.start + marker.length
        : selection.start + selected.length + marker.length * 2;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _focus.requestFocus();
  }

  void _bullet() {
    final value = _controller.value;
    final offset = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final lineStart = offset == 0
        ? 0
        : value.text.lastIndexOf('\n', offset - 1) + 1;
    _controller.value = TextEditingValue(
      text: value.text.replaceRange(lineStart, lineStart, '- '),
      selection: TextSelection.collapsed(offset: offset + 2),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.enabled;
    Widget buildTools(bool narrow) => Row(
      children: [
        _Tool(
          key: const Key('format_bold'),
          icon: Icons.format_bold,
          dense: narrow,
          tooltip: 'Negrito',
          onTap: enabled ? () => _wrap('**') : null,
        ),
        _Tool(
          key: const Key('format_italic'),
          icon: Icons.format_italic,
          dense: narrow,
          tooltip: 'Itálico',
          onTap: enabled ? () => _wrap('_') : null,
        ),
        _Tool(
          key: const Key('format_strike'),
          icon: Icons.format_strikethrough,
          dense: narrow,
          tooltip: 'Riscado',
          onTap: enabled ? () => _wrap('~~') : null,
        ),
        _Tool(
          key: const Key('format_code'),
          icon: Icons.code,
          dense: narrow,
          tooltip: 'Código',
          onTap: enabled ? () => _wrap('`') : null,
        ),
        _Tool(
          key: const Key('format_list'),
          icon: Icons.format_list_bulleted,
          dense: narrow,
          tooltip: 'Lista',
          onTap: enabled ? _bullet : null,
        ),
        Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: colors.borderStrong,
        ),
        _Tool(icon: Icons.add, tooltip: 'Em breve', dense: narrow),
        _Tool(
          icon: Icons.alternate_email,
          tooltip: 'Em breve',
          dense: narrow,
        ),
      ],
    );
    final send = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => FilledButton(
        key: const Key('message_send'),
        onPressed: !enabled || _sending || _controller.text.trim().isEmpty
            ? null
            : _send,
        child: const Text('Enviar'),
      ),
    );
    final hint = Text(
      'Enter envia · Shift + Enter nova linha',
      textAlign: TextAlign.end,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, color: colors.textMuted),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final narrow = box.maxWidth < 560;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            narrow ? 16 : 40,
            0,
            narrow ? 16 : 40,
            28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.borderStrong),
                ),
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('message_field'),
                      controller: _controller,
                      focusNode: _focus,
                      enabled: enabled,
                      minLines: 2,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      cursorColor: colors.accent,
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontSize: 19,
                        color: colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Escrever para ${roomTitle(widget.room)}…',
                        hintStyle: TextStyle(
                          fontFamily: AppFonts.serif,
                          fontSize: 19,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        buildTools(narrow),
                        const SizedBox(width: 12),
                        Expanded(child: narrow ? const SizedBox() : hint),
                        const SizedBox(width: 12),
                        send,
                      ],
                    ),
                    if (narrow) ...[const SizedBox(height: 4), hint],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tool extends StatelessWidget {
  const _Tool({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.dense = false,
  });

  final IconData icon;

  final String tooltip;

  final VoidCallback? onTap;

  final bool dense;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    iconSize: 18,
    visualDensity: VisualDensity.compact,
    style: dense
        ? IconButton.styleFrom(
            minimumSize: const Size(32, 32),
            padding: const EdgeInsets.all(6),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          )
        : null,
    color: context.colors.icon,
    icon: Icon(icon),
  );
}
