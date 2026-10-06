import 'package:flutter/material.dart';

const kPaneAnimationDuration = Duration(milliseconds: 240);

class AnimatedPane extends StatelessWidget {
  const AnimatedPane({
    super.key,
    required this.expanded,
    required this.expandedWidth,
    required this.compactWidth,
    required this.decoration,
    required this.expandedChild,
    required this.compactChild,
    this.hidden = false,
  });

  final bool expanded;

  final double expandedWidth;

  final double compactWidth;

  final BoxDecoration decoration;

  final Widget expandedChild;

  final Widget compactChild;

  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final width = expanded ? expandedWidth : compactWidth;
    return AnimatedContainer(
      duration: kPaneAnimationDuration,
      curve: Curves.easeInOutCubic,
      width: hidden ? 0 : width,
      decoration: decoration,
      clipBehavior: Clip.hardEdge,
      child: AnimatedSwitcher(
        duration: kPaneAnimationDuration,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [
            // A versão que sai não recebe cliques enquanto some.
            for (final child in previous) IgnorePointer(child: child),
            ?current,
          ],
        ),
        child: OverflowBox(
          key: ValueKey(expanded),
          alignment: Alignment.topLeft,
          minWidth: width,
          maxWidth: width,
          child: expanded ? expandedChild : compactChild,
        ),
      ),
    );
  }
}
