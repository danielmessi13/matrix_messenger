import 'package:flutter/material.dart';

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
  });

  final MessageItem message;

  final Future<bool> Function() onRetry;

  final Future<bool> Function() onCancel;

  final Widget? thread;

  // Respostas de thread: corpo menor e sem "Responder em thread".
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = message.isOwn
        ? _OwnMessage(
            message: message,
            onRetry: onRetry,
            onCancel: onCancel,
            compact: compact,
            colors: colors,
          )
        : _OtherMessage(message: message, compact: compact, colors: colors);
    return Column(
      key: Key('message_${message.id}'),
      crossAxisAlignment: message.isOwn
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [content, ?thread],
    );
  }
}

class _OtherMessage extends StatelessWidget {
  const _OtherMessage({
    required this.message,
    required this.compact,
    required this.colors,
  });

  final MessageItem message;

  final bool compact;

  final AppColors colors;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
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
          if (!compact) ...[
            const SizedBox(width: 16),
            _ReplyInThread(colors: colors),
          ],
        ],
      ),
      const SizedBox(height: 6),
      if (message.replyTo case final reply?)
        _ReplyQuote(reply: reply, colors: colors),
      _Body(message: message, colors: colors, italic: false, compact: compact),
    ],
  );
}

class _OwnMessage extends StatelessWidget {
  const _OwnMessage({
    required this.message,
    required this.onRetry,
    required this.onCancel,
    required this.compact,
    required this.colors,
  });

  final MessageItem message;

  final Future<bool> Function() onRetry;

  final Future<bool> Function() onCancel;

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
              if (!compact) ...[
                _ReplyInThread(colors: colors),
                const SizedBox(width: 16),
              ],
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
          if (message.replyTo case final reply?)
            _ReplyQuote(reply: reply, colors: colors),
          _Body(
            message: message,
            colors: colors,
            italic: true,
            compact: compact,
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

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.reply, required this.colors});

  final ReplyPreview reply;

  final AppColors colors;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('message_reply_quote'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.only(left: 10),
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: colors.borderStrong, width: 2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reply.senderName case final name?)
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        Text(
          replyQuoteLabel(reply),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontStyle: reply.state == ReplyState.ready
                ? FontStyle.normal
                : FontStyle.italic,
            color: colors.textMuted,
          ),
        ),
      ],
    ),
  );
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

class _ReplyInThread extends StatelessWidget {
  const _ReplyInThread({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Em breve',
    child: Text(
      'Responder em thread',
      style: TextStyle(
        fontSize: 12.5,
        color: colors.textMuted.withValues(alpha: 0.6),
      ),
    ),
  );
}
