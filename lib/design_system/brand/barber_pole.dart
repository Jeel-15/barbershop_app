import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens/colors.dart';

/// The Rosenthal barber pole as a small object: a glass cylinder with the real
/// stripes of the logo, between two brass caps.
///
/// It draws one moment; it does not animate by itself. [phase] says how far the
/// stripes have turned, in periods (1.0 = one whole stripe), so whoever owns the
/// motion (a finger, a spin) only has to change one number.
///
/// * [phase]  stripes offset, in periods; any value, it wraps.
/// * [glow]   0..1, a soft gold halo around the glass.
/// * [shine]  0..1, a glint on the top cap (one flash: 0 -> 1 -> 0).
class BarberPole extends StatelessWidget {
  const BarberPole({
    super.key,
    this.width = 18,
    this.height = 52,
    this.phase = 0,
    this.glow = 0,
    this.shine = 0,
  });

  /// Width of the glass (the caps are a little wider).
  final double width;

  /// Total height, caps included.
  final double height;
  final double phase;
  final double glow;
  final double shine;

  /// The stripe image is 62 x 96 px: one seamless period.
  static const _strip = 'assets/images/pole_strip.png';
  static const _stripAspect = 96 / 62;

  @override
  Widget build(BuildContext context) {
    final capH = width * 0.5;
    final glassH = height - capH * 2 + 2;
    final period = width * _stripAspect;
    // Where the first stripe starts: a whole number of periods is the logo pose.
    final shift = (phase % 1.0) * period;
    final capW = width + width * 0.2;

    return SizedBox(
      width: capW,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          if (glow > 0)
            Positioned(
              top: capH * 0.4,
              bottom: capH * 0.4,
              left: (capW - width) / 2 - 1,
              width: width + 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(width * 0.3),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.55 * glow),
                      blurRadius: 6 + 14 * glow,
                      spreadRadius: 0.5 + 2 * glow,
                    ),
                  ],
                ),
              ),
            ),
          // The glass with the turning stripes.
          Positioned(
            top: capH - 1,
            height: glassH,
            width: width,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(width * 0.08),
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.hardEdge,
                children: [
                  // The stripes are cut from the logo, which has a dark ground: keep it,
                  // so the glass looks the same on a cream screen.
                  const ColoredBox(color: Color(0xFF17110D)),
                  for (var i = -1; i * period < glassH + period; i++)
                    Positioned(
                      left: 0,
                      width: width,
                      top: shift + i * period,
                      height: period + 0.8,
                      child: Image.asset(
                        _strip,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  // Round like a cylinder: dark edges, a bright band on the left.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Color(0x8C000000),
                          Color(0x00000000),
                          Color(0x59FFFFFF),
                          Color(0x00FFFFFF),
                          Color(0x00000000),
                          Color(0x99000000),
                        ],
                        stops: [0, 0.2, 0.34, 0.5, 0.72, 1],
                      ),
                    ),
                  ),
                  // Shadow where the glass runs into the caps.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x73000000),
                          Color(0x00000000),
                          Color(0x00000000),
                          Color(0x73000000),
                        ],
                        stops: [0, 0.18, 0.82, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The brass caps.
          Positioned.fill(
            child: CustomPaint(
              painter: _CapsPainter(width: width, capH: capH, shine: shine),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brass: a dome on a collar at the top, a collar on a foot at the bottom, with
/// a bright band like the stripes' light and a darker rim.
class _CapsPainter extends CustomPainter {
  _CapsPainter({required this.width, required this.capH, required this.shine});

  final double width;
  final double capH;
  final double shine;

  static const _brass = [
    AppColors.goldDeep,
    AppColors.gold,
    AppColors.goldLight,
    AppColors.gold,
    AppColors.goldDeep,
  ];
  static const _stops = [0.0, 0.25, 0.42, 0.7, 1.0];

  Paint _metal(Rect r) => Paint()
    ..shader = const LinearGradient(
      colors: _brass,
      stops: _stops,
    ).createShader(r);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final capW = size.width;
    final collarH = capH * 0.42;

    // ----- top: dome + collar
    final topCollar = Rect.fromLTWH(0, capH - collarH + 1, capW, collarH);
    final dome = Rect.fromCenter(
      center: Offset(cx, capH - collarH + 2),
      width: width * 0.86,
      height: (capH - collarH) * 2 + 2,
    );
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, capH - collarH + 2));
    canvas.drawOval(dome, _metal(dome));
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(topCollar, Radius.circular(collarH * 0.5)),
      _metal(topCollar),
    );
    // A thin dark line under the collar: where brass meets glass.
    canvas.drawLine(
      Offset(2, topCollar.bottom - 0.4),
      Offset(capW - 2, topCollar.bottom - 0.4),
      Paint()
        ..color = const Color(0x66000000)
        ..strokeWidth = 0.8,
    );

    // ----- bottom: collar + foot
    final by = size.height - capH;
    final botCollar = Rect.fromLTWH(0, by - 1, capW, collarH);
    final foot = Path()
      ..moveTo(width * 0.04 + (capW - width) / 2, by - 1 + collarH - 1)
      ..lineTo(capW - width * 0.04 - (capW - width) / 2, by - 1 + collarH - 1)
      ..lineTo(capW - 1, size.height)
      ..lineTo(1, size.height)
      ..close();
    final footBox = Rect.fromLTWH(
      0,
      by + collarH - 2,
      capW,
      capH - collarH + 2,
    );
    canvas.drawPath(foot, _metal(footBox));
    canvas.drawRRect(
      RRect.fromRectAndRadius(botCollar, Radius.circular(collarH * 0.5)),
      _metal(botCollar),
    );
    canvas.drawLine(
      Offset(2, botCollar.top + 0.4),
      Offset(capW - 2, botCollar.top + 0.4),
      Paint()
        ..color = const Color(0x66000000)
        ..strokeWidth = 0.8,
    );

    // ----- glint on the dome
    if (shine > 0.01) {
      final c = Offset(cx - width * 0.08, capH * 0.45);
      final s = math.sin(math.pi * shine.clamp(0.0, 1.0));
      final r = width * 0.75 * s;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.85 * s),
              AppColors.goldLight.withValues(alpha: 0.3 * s),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: c, radius: r + 0.1)),
      );
      final long = width * 0.8 * s;
      final thin = width * 0.07 * s;
      final star = Path()
        ..moveTo(c.dx, c.dy - long)
        ..quadraticBezierTo(c.dx + thin, c.dy - thin, c.dx + long, c.dy)
        ..quadraticBezierTo(c.dx + thin, c.dy + thin, c.dx, c.dy + long)
        ..quadraticBezierTo(c.dx - thin, c.dy + thin, c.dx - long, c.dy)
        ..quadraticBezierTo(c.dx - thin, c.dy - thin, c.dx, c.dy - long)
        ..close();
      // A gold edge first, so the white star still reads on a cream screen.
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(1.22);
      canvas.translate(-c.dx, -c.dy);
      canvas.drawPath(
        star,
        Paint()..color = AppColors.goldLight.withValues(alpha: 0.9),
      );
      canvas.restore();
      canvas.drawPath(
        star,
        Paint()..color = Colors.white.withValues(alpha: 0.97),
      );
    }
  }

  @override
  bool shouldRepaint(_CapsPainter old) =>
      old.shine != shine || old.width != width || old.capH != capH;
}
