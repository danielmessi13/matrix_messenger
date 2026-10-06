import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';
import '../../../../../core/utils/string_extensions.dart';
import '../../../../conversation/ui/widgets/delayed_indicator.dart';
import '../../../domain/models/message_hit.dart';
import '../../../domain/models/message_search_failure.dart';
import '../view_models/message_search_state.dart';
import 'room_labels.dart';

const _snippetLead = 40;

typedef Snippet = ({String text, List<(int, int)> matches});

Snippet searchSnippet(String body, String query) {
  final text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  final folded = text.foldedForSearch;
  final haystack = folded.length == text.length ? folded : text.toLowerCase();
  final found = <(int, int)>[];
  for (final word in query.foldedForSearch.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    for (
      var i = haystack.indexOf(word);
      i >= 0;
      i = haystack.indexOf(word, i + word.length)
    ) {
      found.add((i, i + word.length));
    }
  }
  found.sort((a, b) => a.$1.compareTo(b.$1));
  final matches = <(int, int)>[];
  for (final match in found) {
    final last = matches.lastOrNull;
    if (last != null && match.$1 <= last.$2) {
      matches[matches.length - 1] = (
        last.$1,
        match.$2 > last.$2 ? match.$2 : last.$2,
      );
    } else {
      matches.add(match);
    }
  }
  if (matches.isEmpty || matches.first.$1 <= _snippetLead) {
    return (text: text, matches: matches);
  }
  var start = matches.first.$1 - _snippetLead;
  final space = text.indexOf(' ', start);
  if (space >= 0 && space < matches.first.$1) start = space + 1;
  final shift = start - 1;
  return (
    text: '…${text.substring(start)}',
    matches: [for (final (a, b) in matches) (a - shift, b - shift)],
  );
}

class MessageResults extends StatelessWidget {
  const MessageResults({
    super.key,
    required this.search,
    required this.query,
    required this.now,
    required this.onOpen,
    required this.onLoadMore,
    required this.onRetry,
  });

  final MessageSearch search;

  final String query;

  final DateTime now;

  final ValueChanged<MessageHit> onOpen;

  final VoidCallback onLoadMore;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final body = switch (search.status) {
      MessageSearchStatus.idle || MessageSearchStatus.loading => const Center(
        child: DelayedIndicator(
          child: CircularProgressIndicator(key: Key('message_search_loading')),
        ),
      ),
      MessageSearchStatus.failed => _Failure(
        type: search.failure ?? MessageSearchFailureType.unknown,
        onRetry: onRetry,
      ),
      MessageSearchStatus.ready when search.hits.isEmpty => const _Notice(
        key: Key('message_search_empty'),
        text: 'Nenhuma mensagem encontrada.',
      ),
      MessageSearchStatus.ready => ListView.builder(
        itemCount: search.hits.length + (search.hasMore ? 1 : 0),
        itemBuilder: (context, index) => index == search.hits.length
            ? _LoadMore(loading: search.loadingMore, onPressed: onLoadMore)
            : _HitTile(
                hit: search.hits[index],
                query: query,
                now: now,
                onTap: () => onOpen(search.hits[index]),
              ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _EncryptedRoomsHint(),
        Expanded(child: body),
      ],
    );
  }
}

class _EncryptedRoomsHint extends StatelessWidget {
  const _EncryptedRoomsHint() : super(key: const Key('encrypted_rooms_hint'));

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 10, 28, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.rowDivider)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 13, color: colors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Salas criptografadas não entram na busca do servidor.',
              style: TextStyle(fontSize: 12.5, color: colors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.query,
    required this.now,
    required this.onTap,
  });

  final MessageHit hit;

  final String query;

  final DateTime now;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = hit.roomName.isEmpty ? 'Sala vazia' : hit.roomName;
    final snippet = searchSnippet(hit.body, query);
    final highlight = TextStyle(
      fontWeight: FontWeight.w600,
      color: colors.textPrimary,
      backgroundColor: colors.accentHighlight,
    );
    final spans = <TextSpan>[
      TextSpan(
        text: '${hit.isOwn ? 'Você' : hit.senderName}: ',
        style: TextStyle(color: colors.textPrimary),
      ),
    ];
    var cursor = 0;
    for (final (start, end) in snippet.matches) {
      spans
        ..add(TextSpan(text: snippet.text.substring(cursor, start)))
        ..add(
          TextSpan(text: snippet.text.substring(start, end), style: highlight),
        );
      cursor = end;
    }
    spans.add(TextSpan(text: snippet.text.substring(cursor)));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('message_hit_${hit.eventId}'),
        onTap: onTap,
        hoverColor: colors.hoverRow,
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.rowDivider)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      hit.isDirect ? name : '# $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.serif,
                        fontSize: 18,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatRoomTime(hit.timestamp, now),
                    style: TextStyle(fontSize: 12.5, color: colors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: spans),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadMore extends StatelessWidget {
  const _LoadMore({required this.loading, required this.onPressed});

  final bool loading;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Center(
      child: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              key: const Key('message_search_more'),
              onPressed: onPressed,
              child: const Text('Mais resultados'),
            ),
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.type, required this.onRetry})
    : super(key: const Key('message_search_failed'));

  final MessageSearchFailureType type;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Notice(
        text: switch (type) {
          MessageSearchFailureType.network => 'Sem conexão com o servidor.',
          MessageSearchFailureType.unknown =>
            'Não foi possível buscar mensagens.',
        },
      ),
      Padding(
        padding: const EdgeInsets.only(left: 20),
        child: TextButton(
          key: const Key('message_search_retry'),
          onPressed: onRetry,
          child: const Text('Tentar de novo'),
        ),
      ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 40, 28, 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 14.5, color: context.colors.textMuted),
    ),
  );
}
