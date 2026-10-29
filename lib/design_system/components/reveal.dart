import 'package:flutter/material.dart';

/// Fades and lifts its child in, [delay] after the screen opens. One
/// controller, no timers: the delay is an interval of the animation.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _length = Duration(milliseconds: 600);
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _length + widget.delay,
  )..forward();
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMilliseconds / (_length + widget.delay).inMilliseconds,
      1,
      curve: Curves.easeOutCubic,
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _a,
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - _a.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}
