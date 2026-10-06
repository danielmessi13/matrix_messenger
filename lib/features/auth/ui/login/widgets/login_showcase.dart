import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';

class LoginShowcase extends StatelessWidget {
  const LoginShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.conversationBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(64, 52, 48, 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Brand(),
            const Spacer(flex: 5),
            const _SampleMessage(
              initials: 'AR',
              author: 'Ana Ribeiro',
              time: '9:02',
              body: 'Bom dia! Alguém já viu o rascunho da proposta?',
            ),
            const SizedBox(height: 24),
            const _SampleMessage(
              initials: 'DA',
              author: 'Diego Alves',
              time: '9:04',
              body: 'Vi sim. Entra aí que eu te mostro.',
              replyTo: (
                author: 'Ana Ribeiro',
                excerpt: 'Bom dia! Alguém já viu o rascunho...',
              ),
            ),
            const Spacer(flex: 6),
            Text(
              'Seu time já está conversando.',
              style: TextStyle(
                fontFamily: AppFonts.serif,
                fontStyle: FontStyle.italic,
                fontSize: 24,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Image.asset('assets/icon/icon.png', width: 40, height: 40),
      const SizedBox(width: 14),
      Text(
        'prosa',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: context.colors.textPrimary,
        ),
      ),
    ],
  );
}

typedef _Reply = ({String author, String excerpt});

class _SampleMessage extends StatelessWidget {
  const _SampleMessage({
    required this.initials,
    required this.author,
    required this.time,
    required this.body,
    this.replyTo,
  });

  static const _avatarSize = 44.0;

  final String initials;
  final String author;
  final String time;
  final String body;
  final _Reply? replyTo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final replyTo = this.replyTo;
    final message = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Initials(initials: initials, size: _avatarSize),
        const SizedBox(width: 16),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: author,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: '  $time',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(fontSize: 16.5, color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ],
    );
    if (replyTo == null) return message;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 24, 14),
      // Recua o destaque para o avatar ficar alinhado com a mensagem de cima.
      transform: Matrix4.translationValues(-14, 0, 0),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReplyPreview(reply: replyTo, avatarSize: _avatarSize),
          const SizedBox(height: 2),
          message,
        ],
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  const _ReplyPreview({required this.reply, required this.avatarSize});

  final _Reply reply;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: avatarSize / 2 + 10,
          height: 10,
          margin: EdgeInsets.only(left: avatarSize / 2, right: 6, bottom: 2),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: colors.accent, width: 1.2),
              top: BorderSide(color: colors.accent, width: 1.2),
            ),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)),
          ),
        ),
        Text(
          reply.author,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            reply.excerpt,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _Initials extends StatelessWidget {
  const _Initials({required this.initials, required this.size});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}
