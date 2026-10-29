import 'dart:math' as math;

import 'package:barbershop_app/design_system/components/haptics.dart';
import 'package:barbershop_app/design_system/tokens/app_tokens.dart';
import 'package:flutter/material.dart';

/// A check mark that draws itself inside a circle that pops in (with a small
/// overshoot). Used where something just worked.
class AnimatedCheck extends StatefulWidget {
  const AnimatedCheck({
    super.key,
    required this.color,
    this.size = 22,
    this.filled = false,
    this.duration = const Duration(milliseconds: 520),
  });

  final Color color;
  final double size;

  /// A solid disc with a white check (big moments) instead of a ring.
  final bool filled;
  final Duration duration;

  @override
  State<AnimatedCheck> createState() => _AnimatedCheckState();
}

class _AnimatedCheckState extends State<AnimatedCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _CheckPainter(
            progress: _c.value,
            color: widget.color,
            filled: widget.filled,
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.progress,
    required this.color,
    required this.filled,
  });

  final double progress;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // The disc pops in over the first 55%, the check draws over the rest.
    final pop = Curves.easeOutBack.transform((progress / 0.55).clamp(0.0, 1.0));
    final draw = Curves.easeOutCubic.transform(
      ((progress - 0.35) / 0.65).clamp(0.0, 1.0),
    );

    if (filled) {
      canvas.drawCircle(c, r * pop, Paint()..color = color);
    } else {
      canvas.drawCircle(
        c,
        r * 0.92 * pop,
        Paint()
          ..color = color.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        c,
        r * 0.92 * pop,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.08,
      );
    }

    final a = Offset(size.width * 0.28, size.height * 0.53);
    final b = Offset(size.width * 0.44, size.height * 0.68);
    final d = Offset(size.width * 0.73, size.height * 0.36);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(d.dx, d.dy);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * draw),
      Paint()
        ..color = filled ? Colors.white : color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = size.width * (filled ? 0.1 : 0.09),
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.progress != progress || old.color != color || old.filled != filled;
}

/// A big moment went well (a booking saved, an invoice paid): a check badge
/// pops in the middle of the screen with a ring and a few sparks, then fades.
/// It never blocks touches, and the screen can close while it plays.
void showSuccessBurst(BuildContext context, {String? label}) {
  AppHaptics.success();
  if (MediaQuery.disableAnimationsOf(context)) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final tokens = context.tokens;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Burst(
      color: tokens.success,
      label: label,
      textColor: tokens.text,
      surface: tokens.surface,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _Burst extends StatefulWidget {
  const _Burst({
    required this.color,
    required this.label,
    required this.textColor,
    required this.surface,
    required this.onDone,
  });

  final Color color;
  final String? label;
  final Color textColor;
  final Color surface;
  final VoidCallback onDone;

  @override
  State<_Burst> createState() => _BurstState();
}

class _BurstState extends State<_Burst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward().whenComplete(widget.onDone);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            // In (0-0.2), hold, out (0.75-1).
            final fade = v < 0.2
                ? v / 0.2
                : (v > 0.75 ? (1 - (v - 0.75) / 0.25) : 1.0);
            final rise = Curves.easeOutCubic.transform(
              (v / 0.3).clamp(0.0, 1.0),
            );
            return Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 10 * (1 - rise)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 22,
                  ),
                  decoration: BoxDecoration(
                    color: widget.surface.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 112,
                        height: 112,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: const Size.square(112),
                              painter: _SparkPainter(v, widget.color),
                            ),
                            AnimatedCheck(
                              color: widget.color,
                              size: 64,
                              filled: true,
                              duration: const Duration(milliseconds: 600),
                            ),
                          ],
                        ),
                      ),
                      if (widget.label != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          widget.label!,
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A ring that grows and fades, and eight sparks that fly out and shrink.
class _SparkPainter extends CustomPainter {
  _SparkPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final go = Curves.easeOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
    final ring = go;
    canvas.drawCircle(
      c,
      size.width * (0.3 + 0.2 * ring),
      Paint()
        ..color = color.withValues(alpha: 0.35 * (1 - ring))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    for (var i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 + (i.isEven ? 0.0 : 0.2);
      final dist = size.width * (0.32 + 0.2 * go);
      final p = c + Offset(math.cos(angle), math.sin(angle)) * dist;
      canvas.drawCircle(
        p,
        (i.isEven ? 4.0 : 2.6) * (1 - go * 0.7),
        Paint()..color = color.withValues(alpha: (1 - go).clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.t != t;
}
