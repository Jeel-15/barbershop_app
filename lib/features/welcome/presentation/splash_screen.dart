import 'dart:math' as math;
import 'dart:ui';

import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:barbershop_app/design_system/design_system.dart';

import 'package:barbershop_app/brand.dart';

/// Black stage and a warm halo. The real Rosenthal crest develops out of a
/// blur, a ring of light passes through it, glints pop on the roses, the
/// barber pole starts to turn and a gold sheen sweeps over the metal. Then it
/// flies into the welcome screen.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5000),
  );
  late final AnimationController _pole = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  late final Animation<double> _sparkles = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.34, 0.78),
  );
  late final Animation<double> _shimmer = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.50, 0.84, curve: Curves.easeInOut),
  );

  bool _leaving = false;

  /// The animation is over but the saved session is still being checked.
  bool _waitingForSession = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_goNext);
  }

  @override
  void dispose() {
    _c.dispose();
    _pole.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_leaving || !mounted) return;
    if (ref.read(sessionControllerProvider) is SessionLoading) {
      _waitingForSession = true;
      return;
    }
    _leaving = true;
    // The router sends a signed-in user straight to the app.
    context.go('/welcome');
  }

  double _seg(double a, double b, [Curve curve = Curves.linear]) {
    return curve.transform(
      ((_c.value - a) / (b - a)).clamp(0.0, 1.0).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionControllerProvider, (_, next) {
      if (_waitingForSession && next is! SessionLoading) {
        _waitingForSession = false;
        _goNext();
      }
    });
    final size = MediaQuery.sizeOf(context);
    // Crest width: as large as comfortable, never taller than ~52% of the screen.
    final crestW = math.min(280.0, size.height * 0.52 / RosenthalCrest.aspect);

    return SystemBars(
      lightIcons: true,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _goNext,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final glow = _seg(0.0, 0.5, Curves.easeOut);
              final breathe = 0.5 + 0.5 * math.sin(_c.value * math.pi * 6);
              final reveal = _seg(0.04, 0.46, Curves.easeOutCubic);
              final ring = _seg(0.10, 0.52, Curves.easeOutCubic);
              final poleOn = _seg(0.40, 0.56);
              final tagline = _seg(0.62, 0.86, Curves.easeOut);
              final loader = _seg(0.0, 0.94);
              final fadeOut = _seg(0.92, 1.0, Curves.easeIn);
              // A blur costs the GPU on every frame it shows: half as strong looks the same.
              final sigma = (1 - reveal) * 9;

              Widget crest = Tilt3D(
                maxAngle: 0.30,
                builder: (context, tilt) => RosenthalCrest(
                  width: crestW,
                  poleSpin: _pole,
                  poleOpacity: poleOn,
                  shimmer: _shimmer,
                  sparkles: _sparkles,
                ),
              );
              if (sigma > 0.4) {
                crest = ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: crest,
                );
              }

              return Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.1),
                        radius: 1.05,
                        colors: [Color(0xFF241810), AppColors.ink],
                      ),
                    ),
                  ),
                  // Breathing brass halo behind the crest.
                  Align(
                    alignment: const Alignment(0, -0.06),
                    child: Container(
                      width: 520 * (0.82 + 0.18 * breathe) * glow,
                      height: 520 * (0.82 + 0.18 * breathe) * glow,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.gold.withValues(
                              alpha: (0.24 + 0.07 * breathe) * glow,
                            ),
                            AppColors.goldDeep.withValues(alpha: 0.08 * glow),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.5, 1],
                        ),
                      ),
                    ),
                  ),
                  // One ring of light that leaves the crest as it appears.
                  if (ring > 0 && ring < 1)
                    Align(
                      alignment: const Alignment(0, -0.06),
                      child: CustomPaint(
                        size: Size.square(crestW * 2.4),
                        painter: _RingPainter(t: ring),
                      ),
                    ),
                  GoldDust(
                    count: 46,
                    opacity: _seg(0.05, 0.4) * (1 - fadeOut * 0.6),
                  ),
                  Align(
                    alignment: const Alignment(0, -0.06),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Opacity(
                            opacity: reveal,
                            child: Transform.scale(
                              scale: 0.86 + 0.14 * reveal,
                              child: Hero(tag: crestHeroTag, child: crest),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Opacity(
                            opacity: 1 - fadeOut,
                            child: _Tagline(
                              t: tagline,
                              text: AppBrand.audience,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 54,
                    child: Opacity(
                      opacity: (1 - fadeOut) * _seg(0.0, 0.1),
                      child: Center(
                        child: Container(
                          width: 120,
                          height: 2,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: loader,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: AppColors.goldGradient,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 * (0.25 + 0.75 * t);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * (1 - t) + 0.4
        ..color = AppColors.goldLight.withValues(alpha: 0.55 * (1 - t))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * (1 - t) + 1),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.t != t;
}

class _Tagline extends StatelessWidget {
  const _Tagline({required this.t, required this.text});

  final double t;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34 * t,
            height: 1,
            color: AppColors.gold.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: AppText.ui(
              12,
              weight: FontWeight.w700,
              letterSpacing: 5.5 - 1.5 * (1 - t),
              color: AppColors.gold,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 34 * t,
            height: 1,
            color: AppColors.gold.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}
