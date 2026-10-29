import 'package:flutter/material.dart';

/// How a screen enters and leaves: it rises a little and fades in (decelerate),
/// the screen under it eases back and dims. 280 ms, one rule for every pushed
/// screen, so forms and details feel like one family (Material "shared axis").
/// With "remove animations" on, the screens simply switch.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final under = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // The screen's own background sits still and fades in with it; only the
    // content rises. Without it the strip the rising screen leaves at the top
    // shows the screen underneath (a near-black splash: a black bar over the
    // status bar while the app opens).
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.9).animate(under),
      child: FadeTransition(
        opacity: enter,
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).animate(enter),
            child: child,
          ),
        ),
      ),
    );
  }
}
