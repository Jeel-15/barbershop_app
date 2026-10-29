import 'dart:math' as math;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/brand/barber_pole.dart';
import 'package:barbershop_app/design_system/components/haptics.dart';
import 'package:barbershop_app/design_system/tokens/app_tokens.dart';
import 'package:barbershop_app/design_system/tokens/colors.dart';
import 'package:barbershop_app/design_system/tokens/typography.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// What the refresh indicator is saying right now.
enum PoleMode {
  /// Being pulled, not far enough yet: "Pull to refresh".
  pulling,

  /// Far enough: "Release to refresh".
  armed,

  /// Loading: the pole turns.
  loading,

  /// Done: "Updated 2:41 PM".
  success,

  /// It did not work: "Couldn't refresh".
  failure,
}

/// Height of the gap the indicator lives in (the pull that arms it).
const double kPoleSlot = 92;

double _smooth(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3 - 2 * x);
}

/// One moment of the "Pole Pull" indicator: the barber pole and one line of
/// words. It is a picture of its inputs, nothing here moves by itself, so every
/// state can be drawn (and reviewed) on its own.
///
/// * [value]   how far it is pulled: 0 = not at all, 1 = armed, up to 1.5.
/// * [phase]   how far the stripes have turned, in periods.
/// * [pop]     0..1, the little hop of the pole when it becomes armed.
/// * [ring]    0..1, the ring of light that leaves the pole once when armed.
/// * [shine]   0..1, the glint on the cap when it is done.
class PoleRefreshFace extends StatelessWidget {
  const PoleRefreshFace({
    super.key,
    required this.value,
    required this.mode,
    required this.phase,
    this.pop = 0,
    this.ring = 0,
    this.shine = 0,
    this.label,
    this.sublabel,
    this.reduceMotion = false,
  });

  final double value;
  final PoleMode mode;
  final double phase;
  final double pop;
  final double ring;
  final double shine;
  final String? label;
  final String? sublabel;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pulling = mode == PoleMode.pulling || mode == PoleMode.armed;

    // Appearing: the pole first, the words a little later.
    final poleIn = pulling ? _smooth(value / 0.35) : 1.0;
    final wordsIn = pulling ? _smooth((value - 0.45) / 0.35) : 1.0;
    final scaleIn = 0.82 + 0.18 * poleIn;

    // Past the point of arming the pole stretches (tension) and glows.
    final stretch = ((value - 1) / 0.5).clamp(0.0, 1.0);
    final hop = reduceMotion
        ? 0.0
        : 0.11 * math.sin(math.pi * pop) * (1 - 0.3 * pop);
    final sy = (scaleIn + hop) * (1 + 0.15 * stretch);
    final sx = (scaleIn + hop) * (1 - 0.08 * stretch);

    final glow = switch (mode) {
      PoleMode.pulling => 0.0,
      PoleMode.armed => 0.25 + 0.6 * stretch,
      PoleMode.loading => 0.32,
      PoleMode.success => 0.3 + 0.4 * shine,
      PoleMode.failure => 0.0,
    };

    final dim = mode == PoleMode.failure ? 0.55 : 1.0;

    final labelColor = switch (mode) {
      PoleMode.success => t.success,
      PoleMode.failure => t.danger,
      _ => t.textSecondary,
    };
    final labelIcon = switch (mode) {
      PoleMode.success => Icons.check_circle_rounded,
      PoleMode.failure => Icons.error_outline_rounded,
      _ => null,
    };

    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: kPoleSlot,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 54,
                width: 76,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (ring > 0 && ring < 1 && !reduceMotion)
                      CustomPaint(
                        size: const Size(76, 54),
                        painter: _RingPainter(ring),
                      ),
                    Opacity(
                      opacity: poleIn * dim,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.diagonal3Values(sx, sy, 1),
                        child: BarberPole(
                          width: 19,
                          height: 54,
                          phase: reduceMotion ? 0 : phase,
                          glow: glow,
                          shine: reduceMotion ? 0 : shine,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Opacity(
                opacity: wordsIn,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 140),
                  child: Column(
                    key: ValueKey('$mode|$label|$sublabel'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (labelIcon != null) ...[
                            Icon(labelIcon, size: 14, color: labelColor),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            label ?? '',
                            style: AppType.label.copyWith(
                              color: labelColor,
                              fontSize: 12.5,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                      if (sublabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            sublabel!,
                            style: AppType.caption.copyWith(
                              color: t.textMuted,
                              fontSize: 10.5,
                              height: 1.1,
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

/// The ring of light that leaves the pole once when it becomes armed.
class _RingPainter extends CustomPainter {
  _RingPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final e = Curves.easeOutCubic.transform(t);
    final rect = Rect.fromCenter(
      center: c,
      width: 22 + 48 * e,
      height: 58 + 20 * e,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.width * 0.4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * (1 - e) + 0.6
        ..color = AppColors.goldLight.withValues(alpha: 0.65 * (1 - e)),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}

/// Pull to refresh with the Rosenthal barber pole.
///
/// The gesture and its states come from `custom_refresh_indicator`; everything
/// that is seen and felt is ours: the pole turns with the finger, hops and sends
/// out a ring when the pull is far enough (with a light tap), spins with weight
/// while the data loads, then slows down with a glint and says "Updated 2:41 PM"
/// (or "Couldn't refresh"). See docs/PULL_TO_REFRESH.md.
class AppRefresh extends StatefulWidget {
  const AppRefresh({super.key, required this.onRefresh, required this.child});

  /// Loads the new data. It may throw: the indicator then says so and the page
  /// keeps what it had.
  final Future<void> Function() onRefresh;

  /// A scroll view that can always scroll (so a short list can be pulled too).
  final Widget child;

  /// Pull needed to arm (the gap that opens).
  static const armedAt = kPoleSlot;

  /// "Refreshing" is shown at least this long, so the motion is seen even when
  /// the data comes from a cache.
  static const minLoading = Duration(milliseconds: 450);

  /// The result is shown this long before the indicator slides away.
  static const resultHold = Duration(milliseconds: 1000);

  @override
  State<AppRefresh> createState() => _AppRefreshState();
}

class _AppRefreshState extends State<AppRefresh> with TickerProviderStateMixin {
  /// One stripe turns for every this many pixels of pull.
  static const _pxPerPeriod = 56.0;

  /// Turns per second while loading (the pole turns downward, like the real one).
  static const _spinSpeed = 1.35;

  final _phase = ValueNotifier<double>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _speed = 0;
  double _target = 0;
  double _rate = 6;

  late final AnimationController _pop;
  late final AnimationController _ring;
  late final AnimationController _shine;

  PoleMode? _result;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    // Made here, not lazily: a ticker cannot be created while the widget is being
    // taken out of the tree (dispose of a page that was never pulled).
    _ticker = createTicker(_onTick);
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _ring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pop.dispose();
    _ring.dispose();
    _shine.dispose();
    _phase.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    // The speed chases its target like a real, heavy object: it winds up and
    // winds down instead of starting and stopping at once.
    _speed += (_target - _speed) * (1 - math.exp(-_rate * dt));
    _phase.value += _speed * dt;
    if (_target == 0 && _speed < 0.02) {
      _speed = 0;
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  void _spin(double target, {double rate = 6}) {
    _target = target;
    _rate = rate;
    if (!_ticker.isActive && (target > 0 || _speed > 0.02)) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _onState(IndicatorStateChange change) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final to = change.newState;
    switch (to) {
      case IndicatorState.armed:
        AppHaptics.select();
        if (!reduce) {
          _pop.forward(from: 0);
          _ring.forward(from: 0);
        }
      case IndicatorState.settling || IndicatorState.loading:
        if (!reduce) _spin(_spinSpeed, rate: 5);
      case IndicatorState.complete:
        _spin(0, rate: 3.5);
        if (_result == PoleMode.success) {
          AppHaptics.tap();
          if (!reduce) _shine.forward(from: 0);
        } else {
          AppHaptics.warning();
        }
      case IndicatorState.idle:
        _result = null;
        _pop.value = 0;
        _ring.value = 0;
        _shine.value = 0;
      default:
        break;
    }
  }

  Future<void> _refresh() async {
    _result = null;
    try {
      // Both: the data, and the minimum time the pole is seen turning.
      await Future.wait([
        widget.onRefresh(),
        Future<void>.delayed(AppRefresh.minLoading),
      ]);
      _result = PoleMode.success;
      _updatedAt = ShopTime.now();
    } catch (_) {
      _result = PoleMode.failure;
    }
  }

  PoleMode _modeOf(IndicatorController c) {
    if (c.isComplete || c.isFinalizing) {
      return _result ?? PoleMode.success;
    }
    if (c.isLoading || c.isSettling) return PoleMode.loading;
    if (c.isArmed) return PoleMode.armed;
    return PoleMode.pulling;
  }

  String _clock(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return CustomRefreshIndicator(
      onRefresh: _refresh,
      onStateChanged: _onState,
      offsetToArmed: AppRefresh.armedAt,
      durations: const RefreshIndicatorDurations(
        cancelDuration: Duration(milliseconds: 280),
        settleDuration: Duration(milliseconds: 180),
        finalizeDuration: Duration(milliseconds: 280),
        completeDuration: AppRefresh.resultHold,
      ),
      builder: (context, child, controller) {
        final v = controller.value;
        // Past the point of arming the content follows the finger at half speed
        // (a rubber band), so the pull has a limit you can feel.
        final eased = v <= 1 ? v : 1 + (v - 1) * 0.5;
        final shift = kPoleSlot * eased;
        final mode = _modeOf(controller);

        // While the finger turns the pole, the stripes follow it, both ways.
        if (controller.isDragging ||
            controller.isArmed ||
            controller.isCanceling) {
          _phase.value = v * AppRefresh.armedAt / _pxPerPeriod;
        }

        final (String label, String? sub) = switch (mode) {
          PoleMode.pulling => (
            'Pull to refresh',
            _updatedAt == null ? null : 'Updated ${_clock(_updatedAt!)}',
          ),
          PoleMode.armed => ('Release to refresh', null),
          PoleMode.loading => ('Refreshing…', null),
          PoleMode.success => (
            _updatedAt == null ? 'Updated' : 'Updated ${_clock(_updatedAt!)}',
            null,
          ),
          PoleMode.failure => ("Couldn't refresh", 'Showing what you had'),
        };

        return Stack(
          // The page keeps filling the space it had (as under a RefreshIndicator).
          fit: StackFit.expand,
          children: [
            // The gap that opens above the content, glued to its top edge.
            Positioned(
              top: shift - kPoleSlot,
              left: 0,
              right: 0,
              height: kPoleSlot,
              // At rest nothing is built (the slot stays, so the page keeps its place).
              child: controller.isIdle && v == 0
                  ? const SizedBox.shrink()
                  : IgnorePointer(
                      child: RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: Listenable.merge([
                            _phase,
                            _pop,
                            _ring,
                            _shine,
                          ]),
                          builder: (context, _) => PoleRefreshFace(
                            value: v,
                            mode: mode,
                            phase: _phase.value,
                            pop: _pop.value,
                            ring: _ring.value,
                            shine: _shine.value,
                            label: label,
                            sublabel: sub,
                            reduceMotion: reduce,
                          ),
                        ),
                      ),
                    ),
            ),
            Transform.translate(offset: Offset(0, shift), child: child),
          ],
        );
      },
      child: widget.child,
    );
  }
}
