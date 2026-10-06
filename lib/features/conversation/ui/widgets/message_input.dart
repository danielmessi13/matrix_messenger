import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme.dart';
import '../../domain/models/timeline_item.dart';
import 'message_labels.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.placeholder,
    required this.onSend,
    this.enabled = true,
    this.replyTo,
    this.onCancelReply,
    this.compact = false,
    this.autofocus = false,
    this.covered = false,
    this.onChanged,
    this.status,
  });

  final String placeholder;

  final bool enabled;

  final Future<bool> Function(String text) onSend;

  final MessageItem? replyTo;

  final VoidCallback? onCancelReply;

  // Painel da thread: sem formatação nem dica.
  final bool compact;

  final bool autofocus;

  // Painel da thread aberto por cima; ao fechar, o campo retoma o foco.
  final bool covered;

  final ValueChanged<String>? onChanged;

  final Widget? status;

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();

  final _focus = FocusNode(debugLabel: 'message_field');

  bool _sending = false;

  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = _onKey;
    _controller.addListener(_onText);
    // O autofocus do campo não tira o foco de outro campo já focado.
    if (widget.autofocus) _focusAfterFrame();
  }

  // Depois do quadro, para o campo já estar habilitado quando o foco for pedido.
  void _focusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(MessageInput old) {
    super.didUpdateWidget(old);
    final target = widget.replyTo;
    if (target != null && target.id != old.replyTo?.id) _focus.requestFocus();
    if (widget.autofocus && widget.enabled && !old.enabled) _focusAfterFrame();
    if (old.covered && !widget.covered) _focusAfterFrame();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  // O listener do controller também dispara em seleção; só repassa quando o texto muda.
  void _onText() {
    final text = _controller.text;
    if (text == _lastText) return;
    _lastText = text;
    widget.onChanged?.call(text);
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
        final hPad = widget.compact ? 20.0 : (box.maxWidth < 560 ? 16.0 : 40.0);
        final narrow = widget.compact || box.maxWidth < 560;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            hPad,
            0,
            hPad,
            28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?widget.status,
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceRaised,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.borderStrong),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.replyTo case final target?)
                          _ReplyBar(
                            target: target,
                            onCancel: widget.onCancelReply,
                          ),
                        TextField(
                          key: const Key('message_field'),
                          controller: _controller,
                          focusNode: _focus,
                          enabled: enabled,
                          autofocus: widget.autofocus,
                          minLines: 2,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          cursorColor: colors.accent,
                          style: TextStyle(
                            fontFamily: AppFonts.serif,
                            fontSize: widget.compact ? 17 : 19,
                            color: colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: widget.placeholder,
                            hintStyle: TextStyle(
                              fontFamily: AppFonts.serif,
                              fontSize: widget.compact ? 17 : 19,
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (!widget.compact)
                              _FormatTools(
                                enabled: enabled,
                                dense: narrow,
                                onWrap: _wrap,
                                onBullet: _bullet,
                              ),
                            const SizedBox(width: 12),
                            Expanded(child: narrow ? const SizedBox() : hint),
                            const SizedBox(width: 12),
                            send,
                          ],
                        ),
                        if (narrow && !widget.compact) ...[
                          const SizedBox(height: 4),
                          hint,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FormatTools extends StatelessWidget {
  const _FormatTools({
    required this.enabled,
    required this.dense,
    required this.onWrap,
    required this.onBullet,
  });

  final bool enabled;

  final bool dense;

  final ValueChanged<String> onWrap;

  final VoidCallback onBullet;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        _Tool(
          key: const Key('format_bold'),
          icon: Icons.format_bold,
          dense: dense,
          tooltip: 'Negrito',
          onTap: enabled ? () => onWrap('**') : null,
        ),
        _Tool(
          key: const Key('format_italic'),
          icon: Icons.format_italic,
          dense: dense,
          tooltip: 'Itálico',
          onTap: enabled ? () => onWrap('_') : null,
        ),
        _Tool(
          key: const Key('format_strike'),
          icon: Icons.format_strikethrough,
          dense: dense,
          tooltip: 'Riscado',
          onTap: enabled ? () => onWrap('~~') : null,
        ),
        _Tool(
          key: const Key('format_code'),
          icon: Icons.code,
          dense: dense,
          tooltip: 'Código',
          onTap: enabled ? () => onWrap('`') : null,
        ),
        _Tool(
          key: const Key('format_list'),
          icon: Icons.format_list_bulleted,
          dense: dense,
          tooltip: 'Lista',
          onTap: enabled ? onBullet : null,
        ),
        Container(
          width: 1,
          height: 20,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: colors.borderStrong,
        ),
        _Tool(icon: Icons.add, tooltip: 'Em breve', dense: dense),
        _Tool(
          icon: Icons.alternate_email,
          tooltip: 'Em breve',
          dense: dense,
        ),
      ],
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

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({required this.target, required this.onCancel});

  final MessageItem target;

  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const Key('reply_bar'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    replyBarLabel(target),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    messageExcerpt(target),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const Key('reply_cancel'),
              tooltip: 'Cancelar resposta',
              onPressed: onCancel,
              icon: Icon(Icons.close, size: 16, color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
