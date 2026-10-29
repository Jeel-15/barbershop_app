import 'package:flutter/material.dart';

/// A small "live" dot: a soft ring grows out of it and fades, once every
/// second and a half, [cycles] times, then it rests (an endless animation keeps
/// the phone drawing 60 frames a second for nothing). Pauses by itself when its
/// screen is not visible and does not move when the phone asks for no animations.
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.size = 8,
    this.cycles = 3,
  });

  final Color color;
  final double size;
  final int cycles;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_started) {
      _started = true;
      _c.repeat(count: widget.cycles);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return RepaintBoundary(
      child: SizedBox(
        width: s * 2.6,
        height: s * 2.6,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = Curves.easeOut.transform(_c.value);
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: s + s * 1.6 * v,
                  height: s + s * 1.6 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.45 * (1 - v)),
                  ),
                ),
                Container(
                  width: s,
                  height: s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
