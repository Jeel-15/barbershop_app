import 'dart:math' as math;

import '../tokens/colors.dart';
import 'package:flutter/material.dart';

/// Gold barber scissors that snip twice, rest, and snip again. Drawn in code
/// (no image or animation file): one controller, one painter, so it costs
/// nothing and stays sharp at any size. Used for "quiet day" empty states.
class SnippingScissors extends StatefulWidget {
  const SnippingScissors({super.key, this.size = 120});

  final double size;

  @override
  State<SnippingScissors> createState() => _SnippingScissorsState();
}

class _SnippingScissorsState extends State<SnippingScissors>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0 = closed, 1 = fully open. Two quick snips, then a pause.
  static double _open(double t) {
    double pulse(double a, double b) {
      if (t < a || t > b) return 0;
      final x = (t - a) / (b - a);
      return math.sin(x * math.pi);
    }

    return math.max(pulse(0.04, 0.2), pulse(0.24, 0.4));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Scissors',
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _ScissorsPainter(open: _open(_c.value), t: _c.value),
          ),
        ),
      ),
    );
  }
}

class _ScissorsPainter extends CustomPainter {
  _ScissorsPainter({required this.open, required this.t});

  final double open;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final pivot = Offset(s * 0.5, s * 0.58);
    final metal = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.goldLight, AppColors.gold, AppColors.goldDeep],
      ).createShader(Offset.zero & size);
    final ring = Paint()
      ..shader = metal.shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round;

    // Soft glow behind.
    canvas.drawCircle(
      pivot.translate(0, -s * 0.12),
      s * 0.42,
      Paint()
        ..shader = RadialGradient(
          colors: [AppColors.gold.withValues(alpha: 0.22), Colors.transparent],
        ).createShader(Rect.fromCircle(center: pivot, radius: s * 0.45)),
    );

    final spread = 0.06 + open * 0.34;
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(side * spread);

      // Blade: a long tapered shape pointing up from the pivot.
      final blade = Path()
        ..moveTo(-side * s * 0.015, 0)
        ..lineTo(side * s * 0.045, 0)
        ..quadraticBezierTo(
          side * s * 0.05,
          -s * 0.32,
          side * s * 0.006,
          -s * 0.52,
        )
        ..quadraticBezierTo(-side * s * 0.03, -s * 0.3, -side * s * 0.015, 0)
        ..close();
      canvas.drawPath(blade, metal);
      canvas.drawPath(
        blade,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = AppColors.ink.withValues(alpha: 0.35),
      );

      // Shank and finger ring below the pivot, crossing to the other side.
      final shank = Path()
        ..moveTo(0, 0)
        ..lineTo(-side * s * 0.1, s * 0.16);
      canvas.drawPath(shank, ring);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(-side * s * 0.15, s * 0.25),
          width: s * 0.2,
          height: s * 0.24,
        ),
        ring,
      );
      canvas.restore();
    }

    // Pivot screw.
    canvas.drawCircle(pivot, s * 0.028, Paint()..color = AppColors.ink);
    canvas.drawCircle(
      pivot,
      s * 0.02,
      Paint()..color = AppColors.goldLight.withValues(alpha: 0.9),
    );

    // A few cut hairs drifting down at the moment of each snip.
    for (var i = 0; i < 4; i++) {
      final start = i < 2 ? 0.14 : 0.34;
      final k = ((t - start - i * 0.012) / 0.3).clamp(0.0, 1.0);
      if (k <= 0 || k >= 1) continue;
      final x =
          pivot.dx + (i - 1.5) * s * 0.09 + math.sin(k * 6 + i) * s * 0.03;
      final y = pivot.dy - s * 0.42 + k * s * 0.55;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(0.6 * (i.isEven ? 1 : -1) + k * 2);
      canvas.drawLine(
        Offset.zero,
        Offset(0, s * 0.07),
        Paint()
          ..color = AppColors.goldLight.withValues(alpha: (1 - k) * 0.9)
          ..strokeWidth = s * 0.014
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ScissorsPainter old) => old.open != open || old.t != t;
}
