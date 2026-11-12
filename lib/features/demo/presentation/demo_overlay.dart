import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/demo/application/demo_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Draws the tour on top of the real app without covering it: a thin gold ring
/// around the control being talked about, a small "finger" where it presses,
/// and a subtitle. No dimming, no blur, nothing that hides the design.
/// All of it ignores touches, so the app underneath behaves exactly as normal.
class DemoOverlay extends ConsumerWidget {
  const DemoOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(demoTourProvider);
    if (!s.active) return const SizedBox.shrink();
    final media = MediaQuery.of(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (s.countdown != null) _Countdown(n: s.countdown!),
              if (kTourFast) const _TestTag(),
              if (s.ring != null) _Ring(rect: s.ring!),
              if (s.dot != null) _Finger(at: s.dot!, pressing: s.pressing),
              if (s.captionsOn && s.caption != null && s.caption!.isNotEmpty)
                _Caption(
                  text: s.caption!,
                  top: s.captionOnTop,
                  safeTop: media.padding.top,
                  safeBottom: media.padding.bottom,
                ),
            ],
          ),
        ),
        // Press and hold the top-left corner to stop the tour.
        Positioned(
          left: 0,
          top: 0,
          width: 72,
          height: 72,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onLongPress: () => ref.read(demoTourProvider.notifier).stop(),
          ),
        ),
      ],
    );
  }
}

class _Ring extends StatefulWidget {
  const _Ring({required this.rect});

  final Rect rect;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  @override
  void initState() {
    super.initState();
    _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rect.inflate(7);
    final radius = (r.shortestSide / 2).clamp(14.0, 26.0);
    return AnimatedPositioned.fromRect(
      rect: r,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          final v = Curves.easeInOut.transform(_pulse.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: AppColors.gold.withValues(alpha: 0.75 + 0.25 * v),
                width: 2.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.30 + 0.25 * v),
                  blurRadius: 10 + 10 * v,
                  spreadRadius: 1 + 2 * v,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Finger extends StatelessWidget {
  const _Finger({required this.at, required this.pressing});

  final Offset at;
  final bool pressing;

  @override
  Widget build(BuildContext context) {
    const size = 46.0;
    return AnimatedPositioned(
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      width: size,
      height: size,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
      child: AnimatedScale(
        scale: pressing ? 0.62 : 1,
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: pressing ? 0.55 : 0.32),
            border: Border.all(color: AppColors.gold, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 10,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.text,
    required this.top,
    required this.safeTop,
    required this.safeBottom,
  });

  final String text;
  final bool top;
  final double safeTop;
  final double safeBottom;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      left: 0,
      right: 0,
      top: top ? safeTop + 10 : null,
      bottom: top ? null : AppNavBar.reservedHeight(context) - 14,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Container(
            key: ValueKey(text),
            constraints: BoxConstraints(maxWidth: width * 0.86),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xE61A1612),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.n});

  final int n;

  @override
  Widget build(BuildContext context) {
    // No dimming: the app stays fully visible behind the number (a soft shadow
    // keeps the digit readable on light and dark screens).
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (c, a) => ScaleTransition(
          scale: Tween(begin: 1.4, end: 1.0).animate(a),
          child: FadeTransition(opacity: a, child: c),
        ),
        child: Text(
          '$n',
          key: ValueKey(n),
          style: const TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 140,
            fontWeight: FontWeight.w700,
            color: AppColors.gold,
            decoration: TextDecoration.none,
            shadows: [Shadow(color: Color(0x99000000), blurRadius: 18)],
          ),
        ),
      ),
    );
  }
}

/// Shown only in test builds that skip the voice, so nobody mistakes a silent
/// test run for a broken sound.
class _TestTag extends StatelessWidget {
  const _TestTag();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: top + 4,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFB3261E),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'TEST RUN · NO VOICE',
          style: TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
