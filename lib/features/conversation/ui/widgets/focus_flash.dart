import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../conversation/view_models/message_search.dart';

const _flashDuration = Duration(milliseconds: 1600);

const _scrollDuration = Duration(milliseconds: 300);

// Rola até a mensagem pedida e a destaca; a lista precisa montar todas (sem lazy).
mixin FocusFlash<T extends StatefulWidget> on State<T> {
  final _keys = <String, GlobalKey>{};

  String? _flashing;

  Timer? _flashTimer;

  String? get flashing => _flashing;

  GlobalKey keyFor(String messageId) =>
      _keys.putIfAbsent(messageId, GlobalKey.new);

  void pruneKeys(Iterable<String> ids) {
    final keep = ids.toSet();
    _keys.removeWhere((id, _) => !keep.contains(id));
  }

  void focusOn(FocusRequest request) {
    // Depois do frame: a key precisa do contexto já montado e o SnackBar não pode sair durante o build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final id = request.messageId;
      if (id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mensagem fora do histórico carregado')),
        );
        return;
      }
      final target = _keys[id]?.currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: _scrollDuration,
        curve: Curves.easeOut,
      );
      setState(() => _flashing = id);
      _flashTimer?.cancel();
      _flashTimer = Timer(_flashDuration, () {
        if (mounted) setState(() => _flashing = null);
      });
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }
}

const _openGap = 10.0;

class MessageHighlight extends StatelessWidget {
  const MessageHighlight({
    super.key,
    required this.flashing,
    this.open = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    required this.child,
  });

  final bool flashing;

  // Raiz da thread aberta no painel.
  final bool open;

  final EdgeInsets padding;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(12);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      // Agrupada a mensagem não tem respiro vertical, e a borda colaria no texto.
      padding: open
          ? padding.copyWith(
              top: max(padding.top, _openGap),
              bottom: max(padding.bottom, _openGap),
            )
          : padding,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: flashing
            ? colors.surfaceHigh
            : open
            ? colors.accent.withValues(alpha: 0.07)
            : Colors.transparent,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: open
              ? colors.accent.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
      child: child,
    );
  }
}
