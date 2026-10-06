import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../app/theme.dart';
import '../../domain/models/timeline_item.dart';
import 'markdown_text.dart';
import 'message_labels.dart';

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onCancel,
    this.thread,
    this.compact = false,
    this.onReply,
    this.onStartThread,
    this.onQuoteTap,
  });

  final MessageItem message;

  final Future<bool> Function() onRetry;

  final Future<bool> Function() onCancel;

  final Widget? thread;

  // Respostas de thread: corpo menor.
  final bool compact;

  final VoidCallback? onReply;

  final VoidCallback? onStartThread;

  final ValueChanged<String>? onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = message.isOwn
        ? _OwnMessage(
            message: message,
            onRetry: onRetry,
            onCancel: onCancel,
            onQuoteTap: onQuoteTap,
            compact: compact,
            colors: colors,
          )
        : _OtherMessage(
            message: message,
            onQuoteTap: onQuoteTap,
            compact: compact,
            colors: colors,
          );
    return _HoverActions(
      messageId: message.id,
      alignEnd: message.isOwn,
      // Sem id do servidor, responder e abrir thread falhariam.
      onReply: message.canReply ? onReply : null,
      onStartThread: message.canReply ? onStartThread : null,
      thread: thread,
      child: content,
    );
  }
}

class _OtherMessage extends StatelessWidget {
  const _OtherMessage({
    required this.message,
    required this.onQuoteTap,
    required this.compact,
    required this.colors,
  });

  final MessageItem message;

  final ValueChanged<String>? onQuoteTap;

  final bool compact;

  final AppColors colors;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 640),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            const SizedBox(width: 10),
            Text(
              formatMessageTime(message.timestamp),
              style: TextStyle(fontSize: 12.5, color: colors.textMuted),
            ),
            if (message.replyTo?.isOwn ?? false) ...[
              const SizedBox(width: 10),
              Text(
                'respondeu a você',
                style: TextStyle(fontSize: 12.5, color: colors.accent),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        _QuotedBody(
          reply: message.replyTo,
          alignEnd: false,
          onQuoteTap: onQuoteTap,
          colors: colors,
          child: _Body(
            message: message,
            colors: colors,
            italic: false,
            compact: compact,
          ),
        ),
      ],
    ),
  );
}

class _OwnMessage extends StatelessWidget {
  const _OwnMessage({
    required this.message,
    required this.onRetry,
    required this.onCancel,
    required this.onQuoteTap,
    required this.compact,
    required this.colors,
  });

  final MessageItem message;

  final Future<bool> Function() onRetry;

  final Future<bool> Function() onCancel;

  final ValueChanged<String>? onQuoteTap;

  final bool compact;

  final AppColors colors;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 640),
    child: Container(
      padding: const EdgeInsets.only(right: 18),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colors.accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatMessageTime(message.timestamp),
                style: TextStyle(fontSize: 12.5, color: colors.textMuted),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'VOCÊ',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.7,
                    color: colors.background,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _QuotedBody(
            reply: message.replyTo,
            alignEnd: true,
            onQuoteTap: onQuoteTap,
            colors: colors,
            child: _Body(
              message: message,
              colors: colors,
              italic: true,
              compact: compact,
            ),
          ),
          const SizedBox(height: 6),
          _Status(
            message: message,
            onRetry: onRetry,
            onCancel: onCancel,
            colors: colors,
          ),
        ],
      ),
    ),
  );
}

class _QuotedBody extends StatelessWidget {
  const _QuotedBody({
    required this.reply,
    required this.alignEnd,
    required this.onQuoteTap,
    required this.colors,
    required this.child,
  });

  final ReplyPreview? reply;

  final bool alignEnd;

  final ValueChanged<String>? onQuoteTap;

  final AppColors colors;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reply = this.reply;
    if (reply == null) return child;
    final mine = reply.isOwn;
    final line = mine ? colors.accent.withValues(alpha: 0.25) : colors.border;
    final name = reply.senderName;
    return Container(
      key: const Key('message_reply_quote'),
      margin: const EdgeInsets.only(bottom: 2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: mine
              ? colors.accent.withValues(alpha: 0.45)
              : colors.borderStrong,
        ),
      ),
      // Largura do conteúdo, mas o cabeçalho ocupa o cartão inteiro.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _quoteMinWidth),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: mine
                    ? colors.accent.withValues(alpha: 0.12)
                    : colors.selectedRow,
                child: Tooltip(
                  message: 'Ir para a mensagem original',
                  child: InkWell(
                    key: const Key('reply_quote_header'),
                    onTap: switch (onQuoteTap) {
                      null => null,
                      final onTap => () => onTap(reply.eventId),
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: line)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.reply,
                            size: 14,
                            color: mine ? colors.accent : colors.textPrimary,
                          ),
                          if (name != null) ...[
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: mine
                                      ? colors.accent
                                      : colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                          Flexible(
                            child: _NoIntrinsicWidth(
                              child: Text(
                                ' · ${replyQuoteLabel(reply)}',
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
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Align(
                  alignment: alignEnd
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _quoteMinWidth = 200.0;

// O trecho citado não define a largura do cartão: ela vem do nome e da resposta, e o trecho ganha reticências.
class _NoIntrinsicWidth extends SingleChildRenderObjectWidget {
  const _NoIntrinsicWidth({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderNoIntrinsicWidth();
}

class _RenderNoIntrinsicWidth extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;
}

// Ancorado no balão, meio acima do canto, como no protótipo; fica numa camada acima para o clique funcionar fora do balão.
class _HoverActions extends StatefulWidget {
  const _HoverActions({
    required this.messageId,
    required this.alignEnd,
    required this.onReply,
    required this.onStartThread,
    required this.thread,
    required this.child,
  });

  final String messageId;

  final bool alignEnd;

  final VoidCallback? onReply;

  final VoidCallback? onStartThread;

  final Widget? thread;

  final Widget child;

  @override
  State<_HoverActions> createState() => _HoverActionsState();
}

class _HoverActionsState extends State<_HoverActions>
    with SingleTickerProviderStateMixin {
  final _link = LayerLink();

  final _portal = OverlayPortalController();

  // O overlay só sai depois que a animação de fechar termina.
  late final _animation =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
        reverseDuration: const Duration(milliseconds: 160),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) _portal.hide();
      });

  late final _curve = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  bool _overMessage = false;

  bool _overBar = false;

  @override
  void dispose() {
    _curve.dispose();
    _animation.dispose();
    super.dispose();
  }

  // Passar do balão para o menu dispara a saída antes da entrada; vale o estado final.
  void _hover({bool? message, bool? bar}) {
    _overMessage = message ?? _overMessage;
    _overBar = bar ?? _overBar;
    if (_overMessage || _overBar) {
      _portal.show();
      _animation.forward();
    } else {
      _animation.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final onReply = widget.onReply;
    final onStartThread = widget.onStartThread;
    final end = widget.alignEnd;
    final hasMenu = onReply != null || onStartThread != null;
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
          offset: Offset(end ? 12 : -12, -20),
          child: MouseRegion(
            onEnter: (_) => _hover(bar: true),
            onExit: (_) => _hover(bar: false),
            child: FadeTransition(
              opacity: _curve,
              // Desce um pouco e cresce a partir do canto preso ao balão.
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -0.25),
                  end: Offset.zero,
                ).animate(_curve),
                child: ScaleTransition(
                  scale: Tween(begin: 0.8, end: 1.0).animate(_curve),
                  alignment: end ? Alignment.topRight : Alignment.topLeft,
                  child: _ActionBar(
                    messageId: widget.messageId,
                    onReply: onReply,
                    onStartThread: onStartThread,
                  ),
                ),
              ),
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
    required this.onReply,
    required this.onStartThread,
  });

  final String messageId;

  final VoidCallback? onReply;

  final VoidCallback? onStartThread;

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
