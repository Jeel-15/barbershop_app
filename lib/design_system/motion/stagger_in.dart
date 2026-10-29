import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The time of the frame being built (the clock animations use, so tests can
/// move it).
Duration _now() => SchedulerBinding.instance.currentFrameTimeStamp;

/// Marks a list that has just opened. Rows built within [window] of that
/// moment come in one after another; rows built later (scrolling, paging) just
/// appear, so scrolling never replays an entrance.
class EntranceScope extends InheritedWidget {
  const EntranceScope({
    super.key,
    required super.child,
    required this.openedAt,
    this.window = const Duration(milliseconds: 600),
  });

  final Duration openedAt;
  final Duration window;

  static EntranceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<EntranceScope>();

  /// True while the list is still "just opened".
  bool get fresh => _now() - openedAt < window;

  @override
  bool updateShouldNotify(EntranceScope oldWidget) => false;
}

/// Holds the moment a list opened, so a rebuild of the page does not start a
/// new entrance. A new [resetKey] (another filter, other data) does.
class EntranceHost extends StatefulWidget {
  const EntranceHost({super.key, this.resetKey, required this.child});

  final Object? resetKey;
  final Widget child;

  @override
  State<EntranceHost> createState() => _EntranceHostState();
}

class _EntranceHostState extends State<EntranceHost> {
  Duration _openedAt = _now();

  @override
  void didUpdateWidget(EntranceHost old) {
    super.didUpdateWidget(old);
    if (old.resetKey != widget.resetKey) _openedAt = _now();
  }

  @override
  Widget build(BuildContext context) =>
      EntranceScope(openedAt: _openedAt, child: widget.child);
}

/// A row that fades and rises in, [index] x 40 ms after its neighbour (only the
/// first few rows, and only inside a fresh [EntranceScope]).
class StaggerIn extends StatefulWidget {
  const StaggerIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  static const _maxAnimated = 8;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _a;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decided once, when the row is first built.
    if (_decided) return;
    _decided = true;
    final scope = EntranceScope.maybeOf(context);
    final animate =
        scope != null &&
        scope.fresh &&
        widget.index < StaggerIn._maxAnimated &&
        !MediaQuery.disableAnimationsOf(context);
    if (!animate) return;
    final delay = Duration(milliseconds: 40 * widget.index);
    const length = Duration(milliseconds: 320);
    final total = length + delay;
    _c = AnimationController(vsync: this, duration: total)..forward();
    _a = CurvedAnimation(
      parent: _c!,
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return widget.child;
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(a),
        child: widget.child,
      ),
    );
  }
}
