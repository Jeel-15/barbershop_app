import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:barbershop_app/design_system/design_system.dart';

import 'package:barbershop_app/brand.dart';
import 'package:barbershop_app/core/config/env.dart';
import 'slide_visuals.dart';

class _Slide {
  const _Slide(this.headline, this.body);
  final String headline;
  final String body;
}

/// Story-style welcome: looping barber video, depth-of-field per slide,
/// progress bars (tap to jump, hold to pause), and an interactive visual on
/// every slide.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  static const _slides = [
    _Slide(
      'Your whole shop,\nin your pocket.',
      "Today's chairs, revenue and tips at a glance. Built for owners and barbers.",
    ),
    _Slide(
      'Every barber.\nEvery chair.',
      'Switch between barbers, spot open gaps and book a walk-in in seconds.',
    ),
    _Slide(
      'Confirm, move,\nor cancel in a tap.',
      'New requests land with you. Approve them, move them to a free slot, or decline.',
    ),
    _Slide(
      'Checkout and\nearnings, built in.',
      'Ring up services and products, add a tip, email the invoice, and watch your commission grow.',
    ),
  ];

  late final AnimationController _story = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..addStatusListener(_onStory);
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat(reverse: true);

  int _index = 0;

  @override
  void initState() {
    super.initState();
    _intro.forward();
    _story.forward();
  }

  @override
  void dispose() {
    _story.dispose();
    _intro.dispose();
    _drift.dispose();
    super.dispose();
  }

  void _onStory(AnimationStatus status) {
    if (status == AnimationStatus.completed && _index < _slides.length - 1) {
      _go(_index + 1);
    }
  }

  void _go(int i) {
    if (i < 0 || i >= _slides.length || i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    _story.forward(from: 0);
  }

  Widget _visual() {
    switch (_index) {
      case 0:
        return const TodayPulse();
      case 1:
        return const BarberDeck();
      case 2:
        return const RequestActionCard();
      default:
        return const InvoiceTicket();
    }
  }

  @override
  Widget build(BuildContext context) {
    final intro = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);

    return SystemBars(
      lightIcons: true,
      child: Scaffold(
        backgroundColor: AppColors.ink,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) {
            final w = MediaQuery.sizeOf(context).width;
            if (d.localPosition.dx < w * 0.3) {
              _go(_index - 1);
            } else if (d.localPosition.dx > w * 0.7) {
              _go(_index + 1);
            }
          },
          onLongPressStart: (_) => _story.stop(),
          onLongPressEnd: (_) => _story.forward(),
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -250) _go(_index + 1);
            if (v > 250) _go(_index - 1);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // --- Background: video with slow push-in -----------------------
              AnimatedBuilder(
                animation: Listenable.merge([intro, _drift]),
                builder: (context, child) {
                  final scale =
                      (1.14 - 0.14 * intro.value) + 0.05 * _drift.value;
                  return Transform.scale(scale: scale, child: child);
                },
                child: const VideoBackground(
                  videoAsset: 'assets/video/shop_reel.mp4',
                  fallbackImage: 'assets/images/barber_working.jpg',
                  imageAlignment: Alignment(0, -0.2),
                  videoAlignment: Alignment(0.45, 0),
                ),
              ),
              // Depth of field: slide 1 is crisp, later slides soften the video
              // so the 3D foreground pops.
              TweenAnimationBuilder<double>(
                tween: Tween(end: _index == 0 ? 0 : 1),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) {
                  final tint = ColoredBox(
                    color: AppColors.ink.withValues(alpha: 0.18 + 0.4 * t),
                  );
                  if (t < 0.02) return tint;
                  return BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
                    child: tint,
                  );
                },
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.center,
                      colors: [Color(0xE6000000), Color(0x00000000)],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
              ),
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x000B0806), Color(0xF20B0806)],
                      stops: [0.0, 0.92],
                    ),
                  ),
                  child: SizedBox.expand(),
                ),
              ),
              const GoldDust(count: 24, opacity: 0.55),

              // --- Foreground ------------------------------------------------
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _StoryBars(
                        story: _story,
                        index: _index,
                        count: _slides.length,
                      ),
                      const SizedBox(height: 14),
                      FadeTransition(
                        opacity: CurvedAnimation(
                          parent: _intro,
                          curve: const Interval(0.3, 0.8),
                        ),
                        child: _TopBar(
                          onSkip: () => _go(_slides.length - 1),
                          showSkip: _index != _slides.length - 1,
                        ),
                      ),
                      Expanded(
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: _intro,
                            curve: const Interval(0.45, 1.0),
                          ),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 700),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween(
                                        begin: 0.92,
                                        end: 1.0,
                                      ).animate(animation),
                                      child: SlideTransition(
                                        position: Tween(
                                          begin: const Offset(0, 0.05),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child: KeyedSubtree(
                                  key: ValueKey(_index),
                                  child: MediaQuery(
                                    // Illustrations are drawn on fixed sizes.
                                    data: MediaQuery.of(context).copyWith(
                                      textScaler: MediaQuery.of(
                                        context,
                                      ).textScaler.clamp(maxScaleFactor: 1.1),
                                    ),
                                    child: _visual(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: WordReveal(
                          key: ValueKey('h$_index'),
                          text: _slides[_index].headline,
                          delay: Duration(
                            milliseconds: _index == 0 ? 900 : 150,
                          ),
                          style: AppText.display(
                            38,
                            weight: FontWeight.w700,
                            height: 1.08,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          child: Text(
                            _slides[_index].body,
                            key: ValueKey('b$_index'),
                            style: AppText.ui(
                              15,
                              color: AppColors.cream.withValues(alpha: 0.8),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SlideTransition(
                        position:
                            Tween(
                              begin: const Offset(0, 0.6),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: _intro,
                                curve: const Interval(
                                  0.5,
                                  1.0,
                                  curve: Curves.easeOutCubic,
                                ),
                              ),
                            ),
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: _intro,
                            curve: const Interval(0.5, 1.0),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              GoldButton(
                                label: 'Sign in',
                                icon: Icons.lock_open_rounded,
                                onTap: () => context.push('/sign-in'),
                              ),
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: () => context.push('/forgot'),
                                child: Text(
                                  'Forgot password?',
                                  style:
                                      AppText.ui(
                                        14,
                                        weight: FontWeight.w700,
                                        color: AppColors.cream.withValues(
                                          alpha: 0.88,
                                        ),
                                      ).copyWith(
                                        decoration: TextDecoration.underline,
                                        decorationColor: AppColors.gold,
                                      ),
                                ),
                              ),
                              Text(
                                'Staff and admin accounts only.',
                                textAlign: TextAlign.center,
                                style: AppText.ui(
                                  11.5,
                                  color: AppColors.cream.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryBars extends StatelessWidget {
  const _StoryBars({
    required this.story,
    required this.index,
    required this.count,
  });

  final AnimationController story;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: story,
      builder: (context, _) {
        return Row(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: Container(
                  height: 3.4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: i < index ? 1 : (i == index ? story.value : 0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSkip, required this.showSkip});

  final VoidCallback onSkip;
  final bool showSkip;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Hero(
          tag: crestHeroTag,
          child: SizedBox(
            width: 36,
            height: 36 * RosenthalCrest.aspect,
            child: RosenthalCrest(),
          ),
        ),
        const SizedBox(width: 11),
        GestureDetector(
          // Review tools (connection test and server switch, design gallery):
          // not in production.
          onLongPress: Env.isProd
              ? null
              : () => context.push('/dev/connection'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppBrand.short,
                style: AppText.display(
                  16,
                  letterSpacing: 3.4,
                  color: AppColors.cream,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppBrand.audience,
                style: AppText.ui(
                  9.5,
                  weight: FontWeight.w800,
                  letterSpacing: 2.6,
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        AnimatedOpacity(
          opacity: showSkip ? 1 : 0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !showSkip,
            child: GestureDetector(
              onTap: onSkip,
              child: Glass(
                radius: 20,
                blur: 12,
                tint: 0.12,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                child: Text(
                  'Skip',
                  style: AppText.ui(12.5, weight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
