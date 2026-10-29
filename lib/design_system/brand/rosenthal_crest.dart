import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// The Rosenthal crest (the web project's real logo) with optional life:
///
/// * [poleSpin]  loops 0 -> 1: the stripes of the barber pole turn, using one
///   seamless period cut out of the logo itself (assets/images/pole_strip.png),
/// * [shimmer]   runs 0 -> 1 once: a gold light sweep across the whole crest,
/// * [sparkles]  runs 0 -> 1 once: glints pop on the roses and the pole cap.
///
/// Without those it is a plain, cheap image, which is what the small emblem on
/// the welcome screen uses. Size comes from [width], or from the incoming
/// constraints, so the same widget can be flown by a Hero.
class RosenthalCrest extends StatelessWidget {
  const RosenthalCrest({
    super.key,
    this.width,
    this.poleSpin,
    this.poleOpacity = 1,
    this.shimmer,
    this.sparkles,
  });

  /// Source image is 622 x 958 px.
  static const double aspect = 958 / 622;
  static const _crest = 'assets/images/rosenthal_crest.png';
  static const _strip = 'assets/images/pole_strip.png';

  // Geometry of the pole's glass, in source-image pixels.
  static const _poleLeft = 281.0;
  static const _poleTop = 229.0;
  static const _poleW = 62.0;
  static const _poleH = 141.0;
  static const _period = 96.0;

  /// Glint positions (source pixels): three roses, the pole cap, the scissors.
  static const _glints = [
    Offset(308, 57),
    Offset(81, 187),
    Offset(521, 187),
    Offset(308, 177),
    Offset(308, 492),
  ];

  final double? width;
  final Animation<double>? poleSpin;
  final double poleOpacity;
  final Animation<double>? shimmer;
  final Animation<double>? sparkles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = width ?? (box.hasBoundedWidth ? box.maxWidth : 200.0);
        final k = w / 622;

        Widget body = SizedBox(
          width: w,
          height: w * aspect,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Image.asset(
                  _crest,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              ),
              if (poleSpin != null && poleOpacity > 0.001)
                Positioned(
                  left: _poleLeft * k,
                  top: _poleTop * k,
                  width: _poleW * k,
                  height: _poleH * k,
                  child: Opacity(
                    opacity: poleOpacity.clamp(0.0, 1.0).toDouble(),
                    child: _Pole(spin: poleSpin!, k: k),
                  ),
                ),
            ],
          ),
        );

        if (shimmer != null) {
          final t = shimmer!;
          body = AnimatedBuilder(
            animation: t,
            builder: (context, child) {
              if (t.value <= 0.001 || t.value >= 0.999) return child!;
              final c = -0.25 + t.value * 1.5;
              return ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    AppColors.goldLight.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0.5),
                    AppColors.goldLight.withValues(alpha: 0.22),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: [
                    (c - 0.12).clamp(0.0, 1.0).toDouble(),
                    (c - 0.05).clamp(0.0, 1.0).toDouble(),
                    c.clamp(0.0, 1.0).toDouble(),
                    (c + 0.05).clamp(0.0, 1.0).toDouble(),
                    (c + 0.12).clamp(0.0, 1.0).toDouble(),
                  ],
                ).createShader(rect),
                child: child,
              );
            },
            child: body,
          );
        }

        if (sparkles != null) {
          body = Stack(
            clipBehavior: Clip.none,
            children: [
              body,
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _GlintPainter(sparkles!, k)),
                ),
              ),
            ],
          );
        }

        return body;
      },
    );
  }
}

/// The turning stripes: four copies of one period stacked and slid down by
/// one period, which loops without a seam. A soft shadow at both ends keeps
/// the glass looking round and hides the join with the brass caps.
class _Pole extends StatelessWidget {
  const _Pole({required this.spin, required this.k});

  final Animation<double> spin;
  final double k;

  @override
  Widget build(BuildContext context) {
    final p = RosenthalCrest._period * k;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          AnimatedBuilder(
            animation: spin,
            builder: (context, _) {
              // Phase 0 matches the logo exactly: a strip starts 23 px below the glass top.
              final y = (-169 + spin.value * RosenthalCrest._period) * k;
              return Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  for (var i = 0; i < 4; i++)
                    Positioned(
                      left: 0,
                      width: RosenthalCrest._poleW * k,
                      top: y + i * p,
                      height: p + 0.9,
                      child: Image.asset(
                        RosenthalCrest._strip,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                ],
              );
            },
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x66000000),
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x66000000),
                ],
                stops: [0, 0.16, 0.84, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlintPainter extends CustomPainter {
  _GlintPainter(this.t, this.k) : super(repaint: t);

  final Animation<double> t;
  final double k;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < RosenthalCrest._glints.length; i++) {
      final start = 0.06 + i * 0.15;
      final local = ((t.value - start) / 0.30).clamp(0.0, 1.0).toDouble();
      if (local <= 0 || local >= 1) continue;
      _star(
        canvas,
        RosenthalCrest._glints[i] * k,
        math.sin(math.pi * local),
        k,
      );
    }
  }

  void _star(Canvas canvas, Offset c, double s, double k) {
    final r = 26 * k * s;
    canvas.drawCircle(
      c,
      r + 0.1,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.85 * s),
            AppColors.goldLight.withValues(alpha: 0.3 * s),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: r + 0.1)),
    );
    final long = 30 * k * s;
    final thin = 3.4 * k * s;
    final star = Path()
      ..moveTo(c.dx, c.dy - long)
      ..quadraticBezierTo(c.dx + thin, c.dy - thin, c.dx + long, c.dy)
      ..quadraticBezierTo(c.dx + thin, c.dy + thin, c.dx, c.dy + long)
      ..quadraticBezierTo(c.dx - thin, c.dy + thin, c.dx - long, c.dy)
      ..quadraticBezierTo(c.dx - thin, c.dy - thin, c.dx, c.dy - long)
      ..close();
    canvas.drawPath(
      star,
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(covariant _GlintPainter old) => old.t != t || old.k != k;
}
