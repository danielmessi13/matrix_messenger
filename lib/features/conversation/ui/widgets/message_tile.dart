import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../rooms/ui/room_list/widgets/room_labels.dart';
import '../../domain/models/timeline_item.dart';
import 'image_message.dart';
import 'markdown_text.dart';
import 'message_labels.dart';
import 'reaction_chips.dart';
import 'reaction_picker.dart';

const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🎉'];

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onCancel,
    this.thread,
    this.compact = false,
    this.continuation = false,
    this.continuedBelow = false,
    this.followedByOwn = false,
    this.onReply,
    this.onStartThread,
    this.onQuoteTap,
    this.onReact,
  });

  final MessageItem message;

  final Future<bool> Function() onRetry;

  final Future<bool> Function() onCancel;

  final Widget? thread;

  // Respostas de thread: corpo menor.
  final bool compact;

  final bool continuation;

  final bool continuedBelow;

  final bool followedByOwn;

  final VoidCallback? onReply;

  final VoidCallback? onStartThread;

  final ValueChanged<String>? onQuoteTap;

  final Future<bool> Function(String key)? onReact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final react = switch (onReact) {
      final onReact? when message.canReact => (String key) async {
        if (await onReact(key) || !context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível reagir.')),
        );
      },
      _ => null,
    };
    final content = message.isOwn
        ? _OwnMessage(
            message: message,
            onRetry: onRetry,
            onCancel: onCancel,
            onQuoteTap: onQuoteTap,
            onReact: react,
            compact: compact,
            continuation: continuation,
            continuedBelow: continuedBelow,
            followedByOwn: followedByOwn,
            colors: colors,
          )
        : _OtherMessage(
            message: message,
            onQuoteTap: onQuoteTap,
            onReact: react,
            compact: compact,
            continuation: continuation,
            continuedBelow: continuedBelow,
            colors: colors,
          );
    return _HoverActions(
      messageId: message.id,
      alignEnd: message.isOwn,
      // Sem id do servidor, responder e abrir thread falhariam.
      onReply: message.canReply ? onReply : null,
      onStartThread: message.canReply ? onStartThread : null,
      time: continuation ? formatMessageTime(message.timestamp) : null,
      thread: thread,
      onReact: react,
      child: content,
    );
  }
}

class _OtherMessage extends StatelessWidget {
  const _OtherMessage({
    required this.message,
    required this.onQuoteTap,
    required this.onReact,
    required this.compact,
    required this.continuation,
    required this.continuedBelow,
    required this.colors,
  });

  final MessageItem message;

  final ValueChanged<String>? onQuoteTap;

  final ValueChanged<String>? onReact;

  final bool compact;

  final bool continuation;

  final bool continuedBelow;

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final avatar = compact ? 32.0 : 40.0;
    final reply = message.replyTo;
    return Container(
      constraints: const BoxConstraints(maxWidth: 640),
      padding: _groupGap(continuation, continuedBelow),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reply != null)
            _ReplyLine(
              reply: reply,
              avatar: avatar,
              connected: !continuation,
              onQuoteTap: onQuoteTap,
              colors: colors,
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (continuation)
                SizedBox(width: avatar)
              else
                _Avatar(
                  key: Key('message_avatar_${message.id}'),
                  initials: initialsOfName(message.senderName),
                  size: avatar,
                  background: colors.surfaceHigh,
                  foreground: colors.textPrimary,
                ),
              const SizedBox(width: _avatarGap),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!continuation) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              message.senderName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          if (reply?.isOwn ?? false) ...[
                            const SizedBox(width: 10),
                            Text(
                              'respondeu a você',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.accent,
                              ),
                            ),
                          ],
                          const SizedBox(width: 10),
                          Text(
                            formatMessageTime(message.timestamp),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    _Body(
                      message: message,
                      colors: colors,
                      italic: false,
                      compact: compact,
                    ),
                    if (message.reactions.isNotEmpty)
                      ReactionChips(
                        messageId: message.id,
                        reactions: message.reactions,
                        alignEnd: false,
                        onReact: onReact,
                        trailing: switch (onReact) {
                          final onReact? => ReactionPickerButton(
                            alignEnd: false,
                            onSelected: onReact,
                            builder: (context, open) => _AddReactionChip(
                              key: Key('reaction_add_${message.id}'),
                              onTap: open,
                            ),
                          ),
                          null => null,
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OwnMessage extends StatelessWidget {
  const _OwnMessage({
    required this.message,
    required this.onRetry,
    required this.onCancel,
    required this.onQuoteTap,
    required this.onReact,
    required this.compact,
    required this.continuation,
    required this.continuedBelow,
    required this.followedByOwn,
    required this.colors,
  });

  final MessageItem message;

  final Future<bool> Function() onRetry;

  final Future<bool> Function() onCancel;

  final ValueChanged<String>? onQuoteTap;

  final ValueChanged<String>? onReact;

  final bool compact;

  final bool continuation;

  final bool continuedBelow;

  final bool followedByOwn;

  final AppColors colors;

  // O recibo fica no último evento lido, então "Lida por" só existe nesta mensagem.
  bool get _showsStatus =>
      !followedByOwn ||
      message.readBy.isNotEmpty ||
      message.sendState == SendState.failed ||
      message.sendState == SendState.rejected;

  @override
  Widget build(BuildContext context) {
    final avatar = compact ? 32.0 : 40.0;
    return Container(
      constraints: const BoxConstraints(maxWidth: 640),
      padding: _groupGap(continuation, continuedBelow),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (message.replyTo case final reply?)
            _ReplyLine(
              reply: reply,
              avatar: avatar,
              connected: !continuation,
              alignEnd: true,
              onQuoteTap: onQuoteTap,
              colors: colors,
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!continuation) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            formatMessageTime(message.timestamp),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Você',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colors.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                    _Body(
                      message: message,
                      colors: colors,
                      italic: true,
                      compact: compact,
                    ),
                    if (message.reactions.isNotEmpty)
                      ReactionChips(
                        messageId: message.id,
                        reactions: message.reactions,
                        alignEnd: true,
                        onReact: onReact,
                        trailing: switch (onReact) {
                          final onReact? => ReactionPickerButton(
                            alignEnd: true,
                            onSelected: onReact,
                            builder: (context, open) => _AddReactionChip(
                              key: Key('reaction_add_${message.id}'),
                              onTap: open,
                            ),
                          ),
                          null => null,
                        },
                      ),
                    if (_showsStatus) ...[
                      const SizedBox(height: 6),
                      _Status(
                        message: message,
                        onRetry: onRetry,
                        onCancel: onCancel,
                        colors: colors,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: _avatarGap),
              if (continuation)
                SizedBox(width: avatar)
              else
                _Avatar(
                  key: Key('message_avatar_${message.id}'),
                  initials: 'VC',
                  size: avatar,
                  background: colors.accent,
                  foreground: colors.onAccent,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// Linha da citação acima do cabeçalho; o conector liga o avatar de quem respondeu à mensagem citada.
class _ReplyLine extends StatelessWidget {
  const _ReplyLine({
    required this.reply,
    required this.avatar,
    required this.connected,
    required this.onQuoteTap,
    required this.colors,
    this.alignEnd = false,
  });

  final ReplyPreview reply;

  final double avatar;

  // Continuação não tem avatar: a citação só recua até o texto.
  final bool connected;

  // Mensagem própria: avatar à direita, então a linha é espelhada.
  final bool alignEnd;

  final ValueChanged<String>? onQuoteTap;

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final mine = reply.isOwn;
    // Resposta a mim mesmo: o cabeçalho já diz "Você".
    final name = mine ? (alignEnd ? null : 'Você') : reply.senderName;
    final connector = connected
        ? CustomPaint(
            size: Size(avatar + _avatarGap, _replyLineHeight),
            painter: _ReplyConnector(
              x: avatar / 2,
              mirrored: alignEnd,
              color: mine ? colors.accent : colors.borderStrong,
            ),
          )
        : SizedBox(width: avatar + _avatarGap);
    final quote = <Widget>[
      if (name != null) ...[
        _Avatar(
          initials: mine ? 'VC' : initialsOfName(name),
          size: 20,
          background: mine ? colors.accent : colors.surfaceHigh,
          foreground: mine ? colors.onAccent : colors.textPrimary,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: mine ? colors.accent : colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
      Flexible(
        child: Text(
          replyQuoteLabel(reply),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontStyle: reply.state == ReplyState.ready
                ? FontStyle.normal
                : FontStyle.italic,
            color: colors.textSecondary,
          ),
        ),
      ),
    ];
    return Row(
      key: const Key('message_reply_quote'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!alignEnd) connector,
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(bottom: _replyLineGap),
            child: Tooltip(
              message: 'Ir para a mensagem original',
              child: InkWell(
                key: const Key('reply_quote_header'),
                borderRadius: BorderRadius.circular(10),
                onTap: switch (onQuoteTap) {
                  null => null,
                  final onTap => () => onTap(reply.eventId),
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: alignEnd ? quote.reversed.toList() : quote,
                ),
              ),
            ),
          ),
        ),
        if (alignEnd) connector,
      ],
    );
  }
}

const _avatarGap = 12.0;

const _replyLineHeight = 20.0 + _replyLineGap;

const _replyLineGap = 6.0;

// Sobe do topo do avatar e faz a curva até a linha da citação.
class _ReplyConnector extends CustomPainter {
  const _ReplyConnector({
    required this.x,
    required this.mirrored,
    required this.color,
  });

  final double x;

  final bool mirrored;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 8.0;
    final y = (size.height - _replyLineGap) / 2;
    if (mirrored) {
      canvas
        ..translate(size.width, 0)
        ..scale(-1, 1);
    }
    final path = Path()
      ..moveTo(x, size.height)
      ..lineTo(x, y + radius)
      ..quadraticBezierTo(x, y, x + radius, y)
      ..lineTo(size.width - 4, y);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ReplyConnector oldDelegate) =>
      oldDelegate.x != x ||
      oldDelegate.mirrored != mirrored ||
      oldDelegate.color != color;
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    super.key,
    required this.initials,
    required this.size,
    required this.background,
    required this.foreground,
  });

  final String initials;

  final double size;

  final Color background;

  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: background, shape: BoxShape.circle),
    child: Text(
      initials,
      style: TextStyle(
        fontSize: size * 0.38,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
    ),
  );
}

EdgeInsets _groupGap(bool continuation, bool continuedBelow) => EdgeInsets.only(
  top: continuation ? 3 : 0,
  bottom: continuedBelow ? 3 : 0,
);

// Ancorado no balão, ao lado do canto superior; fica numa camada acima para o clique funcionar fora do balão.
class _HoverActions extends StatefulWidget {
  const _HoverActions({
    required this.messageId,
    required this.alignEnd,
    required this.onReply,
    required this.onStartThread,
    required this.time,
    required this.thread,
    required this.onReact,
    required this.child,
  });

  final String messageId;

  final bool alignEnd;

  final VoidCallback? onReply;

  final VoidCallback? onStartThread;

  final String? time;

  final Widget? thread;

  final ValueChanged<String>? onReact;

  final Widget child;

  @override
  State<_HoverActions> createState() => _HoverActionsState();
}

class _HoverActionsState extends State<_HoverActions> {
  final _link = LayerLink();

  final _portal = OverlayPortalController();

  bool _overMessage = false;

  bool _overBar = false;

  bool _pickerOpen = false;

  // Passar do balão para o menu dispara a saída antes da entrada; vale o estado final.
  void _hover({bool? message, bool? bar}) {
    _overMessage = message ?? _overMessage;
    _overBar = bar ?? _overBar;
    // Com o seletor aberto o mouse está nele, fora da mensagem e da barra.
    if (_overMessage || _overBar || _pickerOpen) {
      // Mostrar de novo traz a barra para cima do seletor, que é filho dela.
      if (!_portal.isShowing) _portal.show();
    } else if (_portal.isShowing) {
      _portal.hide();
    }
  }

  void _pickerChanged(bool open) {
    _pickerOpen = open;
    if (open) {
      _hover();
      return;
    }
    // Pode vir do dispose do seletor, em plena desmontagem da árvore, onde o portal não aceita hide.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hover();
    });
  }

  @override
  Widget build(BuildContext context) {
    final onReply = widget.onReply;
    final onStartThread = widget.onStartThread;
    final end = widget.alignEnd;
    final time = widget.time;
    final onReact = widget.onReact;
    final hasMenu =
        onReply != null ||
        onStartThread != null ||
        time != null ||
        onReact != null;
    Widget row(Widget bubble) => SizedBox(
      width: double.infinity,
      child: Column(
        key: Key('message_${widget.messageId}'),
        crossAxisAlignment: end
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [bubble, ?widget.thread],
      ),
    );
    if (!hasMenu) return row(widget.child);
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          // Cresce para o lado oposto à borda da tela: balão curto colado na direita não empurra o menu para fora.
          targetAnchor: end ? Alignment.topLeft : Alignment.topRight,
          followerAnchor: end ? Alignment.topRight : Alignment.topLeft,
          // Fora do balão, para não cobrir a hora no cabeçalho.
          offset: Offset(end ? -12 : 12, -20),
          child: MouseRegion(
            onEnter: (_) => _hover(bar: true),
            onExit: (_) => _hover(bar: false),
            child: _ActionBar(
              messageId: widget.messageId,
              time: time,
              onReply: onReply,
              onStartThread: onStartThread,
              onReact: onReact,
              alignEnd: end,
              onPickerChanged: _pickerChanged,
            ),
          ),
        ),
      ),
      // A região cobre a linha toda; só o balão serve de âncora do menu.
      child: MouseRegion(
        onEnter: (_) => _hover(message: true),
        onExit: (_) => _hover(message: false),
        child: row(CompositedTransformTarget(link: _link, child: widget.child)),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.messageId,
    required this.time,
    required this.onReply,
    required this.onStartThread,
    required this.onReact,
    required this.alignEnd,
    required this.onPickerChanged,
  });

  final String messageId;

  final String? time;

  final VoidCallback? onReply;

  final VoidCallback? onStartThread;

  final ValueChanged<String>? onReact;

  final bool alignEnd;

  final ValueChanged<bool> onPickerChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.activeFilter,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderStrong),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (time case final time?)
              Padding(
                key: Key('message_time_$messageId'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(
                  time,
                  style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                ),
              ),
            if (onReact case final onReact?) ...[
              for (final emoji in _quickReactions)
                _QuickReaction(
                  key: Key('quick_reaction_${messageId}_$emoji'),
                  emoji: emoji,
                  onTap: () => onReact(emoji),
                ),
              ReactionPickerButton(
                alignEnd: alignEnd,
                onSelected: onReact,
                onOpenChanged: onPickerChanged,
                builder: (context, open) => _IconAction(
                  key: Key('reaction_picker_$messageId'),
                  icon: Icons.add_reaction_outlined,
                  tooltip: 'Reagir',
                  onTap: open,
                ),
              ),
            ],
            if (onReply case final onReply?)
              _ActionButton(
                key: Key('message_reply_$messageId'),
                icon: Icons.reply,
                label: 'Responder',
                onTap: onReply,
              ),
            if (onStartThread case final onStartThread?)
              _ActionButton(
                key: Key('message_thread_$messageId'),
                icon: Icons.forum_outlined,
                label: 'Thread',
                onTap: onStartThread,
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickReaction extends StatefulWidget {
  const _QuickReaction({super.key, required this.emoji, required this.onTap});

  final String emoji;

  final VoidCallback onTap;

  @override
  State<_QuickReaction> createState() => _QuickReactionState();
}

class _QuickReactionState extends State<_QuickReaction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _hovered ? context.colors.surfaceHigh : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 16)),
        ),
      ),
    ),
  );
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;

  final String tooltip;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: Icon(icon, size: 16, color: context.colors.textSecondary),
        ),
      ),
    ),
  );
}

class _AddReactionChip extends StatelessWidget {
  const _AddReactionChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: 'Reagir',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: colors.surfaceHigh,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: colors.borderStrong),
            ),
            child: Icon(
              Icons.add_reaction_outlined,
              size: 15,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;

  final String label;

  final VoidCallback onTap;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final foreground = _hovered ? colors.textPrimary : colors.textSecondary;
    // O InkWell pintava o hover no Material, por baixo do fundo opaco da barra.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceHigh : null,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 15, color: foreground),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: TextStyle(fontSize: 12.5, color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.message,
    required this.colors,
    required this.italic,
    required this.compact,
  });

  final MessageItem message;

  final AppColors colors;

  final bool italic;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (message.image case final image?) {
      return ImageMessage(image: image, alignEnd: italic);
    }
    final placeholder = kindPlaceholder(message.kind);
    final base = TextStyle(
      fontFamily: AppFonts.serif,
      fontSize: compact ? 16 : 20,
      height: 1.5,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: colors.textPrimary,
    );
    if (placeholder != null || message.body == null) {
      return Text(
        placeholder ?? '',
        textAlign: italic ? TextAlign.end : TextAlign.start,
        style: base.copyWith(
          fontStyle: FontStyle.italic,
          color: colors.textMuted,
          fontSize: compact ? 14.5 : 17,
        ),
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          markdownSpan(
            message.body!,
            style: base,
            codeStyle: TextStyle(
              fontFamily: 'monospace',
              fontSize: compact ? 13.5 : 16,
              backgroundColor: colors.surfaceHigh,
            ),
          ),
          if (message.edited)
            TextSpan(
              text: ' (editada)',
              style: TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.normal,
                color: colors.textMuted,
              ),
            ),
        ],
      ),
      textAlign: italic ? TextAlign.end : TextAlign.start,
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.message,
    required this.onRetry,
    required this.onCancel,
    required this.colors,
  });

  final MessageItem message;

  final Future<bool> Function() onRetry;

  final Future<bool> Function() onCancel;

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: colors.textMuted);
    final error = Theme.of(context).colorScheme.error;
    return switch (message.sendState) {
      SendState.sending => Text('Enviando…', style: muted),
      SendState.sent => Text(
        message.readBy.isEmpty ? 'Enviada' : readByLabel(message.readBy),
        style: muted,
      ),
      SendState.failed || SendState.rejected => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Não enviada', style: muted.copyWith(color: error)),
          if (message.sendState == SendState.failed) ...[
            Text(' · ', style: muted),
            _Action(
              key: const Key('message_retry'),
              label: 'Tentar de novo',
              failure: 'Não foi possível reenviar.',
              color: error,
              onTap: onRetry,
            ),
          ],
          Text(' · ', style: muted),
          _Action(
            key: const Key('message_cancel'),
            label: 'Cancelar',
            failure: 'Não foi possível cancelar o envio.',
            color: colors.textSecondary,
            onTap: onCancel,
          ),
        ],
      ),
    };
  }
}

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.label,
    required this.failure,
    required this.color,
    required this.onTap,
  });

  final String label;

  final String failure;

  final Color color;

  final Future<bool> Function() onTap;

  Future<void> _run(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (await onTap()) return;
    messenger.showSnackBar(SnackBar(content: Text(failure)));
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _run(context),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    ),
  );
}
