import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../../app/theme.dart';

class RoomSearchField extends StatefulWidget {
  const RoomSearchField({
    super.key,
    required this.focusNode,
    required this.onChanged,
    required this.onCleared,
  });

  final FocusNode focusNode;

  final ValueChanged<String> onChanged;

  final VoidCallback onCleared;

  @override
  State<RoomSearchField> createState() => _RoomSearchFieldState();
}

class _RoomSearchFieldState extends State<RoomSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onCleared();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shortcut = defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘ K'
        : 'Ctrl K';
    return ListenableBuilder(
      listenable: Listenable.merge([widget.focusNode, _controller]),
      builder: (context, _) => Container(
        height: 42,
        padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.focusNode.hasFocus
                ? colors.accent
                : colors.borderStrong,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 16, color: colors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('room_search'),
                controller: _controller,
                focusNode: widget.focusNode,
                onChanged: widget.onChanged,
                style: TextStyle(fontSize: 15, color: colors.textPrimary),
                cursorColor: colors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Buscar conversas',
                  hintStyle: TextStyle(color: colors.textMuted),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              IconButton(
                key: const Key('room_search_clear'),
                tooltip: 'Limpar busca',
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                color: colors.textMuted,
                onPressed: _clear,
                icon: const Icon(Icons.close),
              ),
            const _ScopeChip(label: 'Tudo', active: true),
            const _ScopeChip(label: 'Mensagens', active: false),
            const _ScopeChip(label: 'Pessoas', active: false),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: colors.borderStrong),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                shortcut,
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, required this.active});

  final String label;

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final chip = Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? colors.borderStrong : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          color: active ? colors.textPrimary : colors.textMuted,
        ),
      ),
    );
    return active ? chip : Tooltip(message: 'Em breve', child: chip);
  }
}
