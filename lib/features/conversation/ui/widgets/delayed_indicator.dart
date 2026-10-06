import 'dart:async';

import 'package:flutter/material.dart';

// Buscas que o cache local resolve terminam antes disto; mostrar o indicador na hora só faria a tela piscar.
const kLoadingIndicatorDelay = Duration(milliseconds: 250);

class DelayedIndicator extends StatefulWidget {
  const DelayedIndicator({super.key, required this.child});

  final Widget child;

  @override
  State<DelayedIndicator> createState() => _DelayedIndicatorState();
}

class _DelayedIndicatorState extends State<DelayedIndicator> {
  late final Timer _timer;

  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
      kLoadingIndicatorDelay,
      () => setState(() => _visible = true),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _visible ? widget.child : const SizedBox.shrink();
}
