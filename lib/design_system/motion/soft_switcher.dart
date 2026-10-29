import 'package:flutter/material.dart';

/// Swaps one view for another (a tab's content, loading -> content) with a
/// short cross-fade and a small rise, and lets the height follow, so the page
/// below does not jump. Give each view its own [ValueKey].
class SoftSwitcher extends StatelessWidget {
  const SoftSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 240),
    this.animateSize = true,
  });

  final Widget child;
  final Duration duration;

  /// Follow the height of the new view (off when the view fills a fixed box).
  final bool animateSize;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final switcher = AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: child,
    );
    return animateSize
        ? AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: switcher,
          )
        : switcher;
  }
}
