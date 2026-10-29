import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// Slow rising gold particles. Loops seamlessly (every particle completes a
/// whole number of cycles per loop) and repaints from a single controller.
class GoldDust extends StatefulWidget {
  const GoldDust({super.key, this.count = 40, this.opacity = 1});

  final int count;
  final double opacity;

  @override
  State<GoldDust> createState() => _GoldDustState();
}

class _GoldDustState extends State<GoldDust>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();
  late final List<_Particle> _particles = _generate(widget.count);

  static List<_Particle> _generate(int n) {
    final r = math.Random(11);
    return List.generate(n, (_) {
      return _Particle(
        x: r.nextDouble(),
        y: r.nextDouble(),
        cycles: 1 + r.nextInt(3),
        size: 0.7 + r.nextDouble() * 2.1,
        phase: r.nextDouble(),
        sway: 0.01 + r.nextDouble() * 0.03,
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _DustPainter(_c, _particles, widget.opacity),
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.cycles,
    required this.size,
    required this.phase,
    required this.sway,
  });

  final double x;
  final double y;
  final int cycles;
  final double size;
  final double phase;
  final double sway;
}

class _DustPainter extends CustomPainter {
  _DustPainter(this.t, this.particles, this.opacity) : super(repaint: t);

  final Animation<double> t;
  final List<_Particle> particles;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final core = Paint();
    for (final p in particles) {
      final travel = (p.y - t.value * p.cycles) % 1.0;
      final y = (travel + 1.0) % 1.0;
      final x =
          p.x + math.sin((t.value * p.cycles + p.phase) * math.pi * 2) * p.sway;
      final twinkle =
          0.55 +
          0.45 * math.sin((t.value * (p.cycles + 2) + p.phase) * math.pi * 2);
      final edge = math.min(1.0, math.min(y, 1 - y) * 5);
      final a = (twinkle * edge * opacity).clamp(0.0, 1.0).toDouble();
      final center = Offset(x * size.width, y * size.height);

      if (p.size > 1.6) {
        glow.color = AppColors.gold.withValues(alpha: a * 0.5);
        canvas.drawCircle(center, p.size * 2.2, glow);
      }
      core.color = AppColors.goldLight.withValues(alpha: a * 0.9);
      canvas.drawCircle(center, p.size * 0.55, core);
    }
  }

  @override
  bool shouldRepaint(covariant _DustPainter oldDelegate) =>
      oldDelegate.opacity != opacity;
}
