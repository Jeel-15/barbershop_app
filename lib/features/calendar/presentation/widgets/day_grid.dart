import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/domain/day_timeline.dart';
import 'package:flutter/material.dart';

String clockLabel(int minutes) {
  final h = minutes ~/ 60 % 24;
  final m = minutes % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

/// Why a tapped spot cannot take a booking, in words (the web says "Staff Not
/// Available" for the working-hours cases).
String slotBlockedMessage(
  SlotVerdict why,
  CalendarLane lane,
  int minutes,
) => switch (why) {
  SlotVerdict.dayOff => '${lane.name} has the day off.',
  SlotVerdict.shopClosed => 'The shop is closed on this day.',
  SlotVerdict.onBreak =>
    '${lane.name} is on a break at ${clockLabel(minutes)}.',
  SlotVerdict.booked => '${lane.name} is booked at ${clockLabel(minutes)}.',
  SlotVerdict.unavailable || SlotVerdict.free =>
    'Staff Not Available: ${lane.name} is not available at ${clockLabel(minutes)}.',
};

String _hourLabel(int hour) {
  final h = hour % 24;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12 ${h < 12 ? 'AM' : 'PM'}';
}

/// "1h 30m", "45m".
String spanLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// The day: a time axis on the left and one column per barber, the barber row
/// pinned on top. Free working time is green, what cannot be booked is hatched,
/// every booking is coloured by its status, a line marks "now".
///
/// Taps follow the web: only free working time starts a booking (first tap
/// marks the spot, a second tap on the mark opens the form); a booking opens
/// its details; anything else says why it cannot be booked ([onBlocked]).
class DayGrid extends StatefulWidget {
  const DayGrid({
    super.key,
    required this.day,
    required this.date,
    required this.onEventTap,
    this.onSlotTap,
    this.onBlocked,
    this.onLaneLongPress,
    this.focus = const {},
    this.bottomPadding = 0,
    this.zoom = kHourDefault,
    this.onZoom,
    this.showHint = false,
    this.onHintSeen,
  });

  final CalendarDay day;
  final DateTime date;
  final ValueChanged<CalendarEvent> onEventTap;

  /// The marked free spot was tapped: (barber id, minutes since midnight).
  final void Function(int laneId, int minutes)? onSlotTap;

  /// A spot that cannot take a booking was tapped.
  final void Function(SlotVerdict why, CalendarLane lane, int minutes)?
  onBlocked;

  /// A barber's header was held: open the staff / column-order sheet.
  final ValueChanged<CalendarLane>? onLaneLongPress;

  /// Status codes to keep bright (the legend's choice); empty = all.
  final Set<int> focus;

  /// Space the floating nav bar needs at the end of the scroll.
  final double bottomPadding;

  /// Pixels per hour (pinch to zoom). The grid keeps its own live value while
  /// two fingers are down and reports the final one through [onZoom].
  final double zoom;
  final ValueChanged<double>? onZoom;

  /// Show the one-time "pinch with two fingers" tip; [onHintSeen] closes it.
  final bool showHint;
  final VoidCallback? onHintSeen;

  static const double gutter = 50;

  /// The default pixels per hour (what [zoom] is at "1x").
  static const double hourHeight = kHourDefault;
  static const double headerHeight = 64;

  @override
  State<DayGrid> createState() => _DayGridState();
}

class _Mark {
  const _Mark(this.laneId, this.minute, this.length);

  final int laneId;
  final int minute;
  final int length;
}

class _DayGridState extends State<DayGrid> with SingleTickerProviderStateMixin {
  final _vertical = ScrollController();
  final _hBody = ScrollController();
  final _hHead = ScrollController();
  final _viewport = GlobalKey();
  Timer? _tick;
  bool _syncing = false;
  _Mark? _mark;

  // ---- pinch to zoom
  /// Pixels per hour right now (the live value while pinching or animating).
  late double _hour = widget.zoom.clamp(kHourMin, kHourMax);
  final _fingers = <int, Offset>{};
  bool _pinching = false;

  /// Taps that end a pinch are not taps (two fingers lifting on a booking).
  bool _quiet = false;
  double _startDist = 1;
  double _startHour = kHourDefault;
  double _anchorHours = 0; // hours from the top of the grid, under the fingers
  double _focusY = 0; // where the fingers are inside the viewport
  bool _crossed = false;
  bool _pill = false;
  Timer? _pillTimer;
  late final AnimationController _glide;
  Animation<double>? _glideTween;

  void _showPill() {
    _pillTimer?.cancel();
    if (!_pill) setState(() => _pill = true);
  }

  void _hidePillSoon() {
    _pillTimer?.cancel();
    _pillTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _pill = false);
    });
  }

  double _viewportTop() {
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.attached ? 0 : box.localToGlobal(Offset.zero).dy;
  }

  double _viewportHeight() {
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.size.height : 600;
  }

  /// Sets the hour height and scrolls so [_anchorHours] stays at [_focusY].
  void _applyHour(double next) {
    final from = _range(_timelines());
    final hours = from.end - from.start;
    final total = hours * next + widget.bottomPadding;
    final maxScroll = (total - _viewportHeight()).clamp(0.0, double.infinity);
    final target = (_anchorHours * next - _focusY).clamp(0.0, maxScroll);
    setState(() => _hour = next);
    if (_vertical.hasClients) _vertical.jumpTo(target);
  }

  void _pointerDown(PointerDownEvent e) {
    _fingers[e.pointer] = e.position;
    if (_fingers.length == 2) _beginPinch();
  }

  void _beginPinch() {
    _glide.stop();
    final pts = _fingers.values.toList();
    _startDist = (pts[0] - pts[1]).distance.clamp(24, double.infinity);
    _startHour = _hour;
    _focusY = (pts[0].dy + pts[1].dy) / 2 - _viewportTop();
    _anchorHours =
        ((_vertical.hasClients ? _vertical.offset : 0) + _focusY) / _hour;
    _crossed = false;
    _quiet = true;
    setState(() {
      _pinching = true;
      _mark = null;
    });
    _showPill();
    if (widget.showHint) widget.onHintSeen?.call();
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    _fingers[e.pointer] = e.position;
    if (!_pinching || _fingers.length < 2) return;
    final pts = _fingers.values.take(2).toList();
    final dist = (pts[0] - pts[1]).distance;
    final next = (_startHour * dist / _startDist).clamp(kHourMin, kHourMax);
    // A small tick when passing 1x and when hitting an end.
    final across = (next - kHourDefault).abs() < 3;
    if (across && !_crossed) AppHaptics.select();
    _crossed = across;
    if ((next - _hour).abs() < 0.05) return;
    if ((next == kHourMin || next == kHourMax) && _hour != next) {
      AppHaptics.select();
    }
    _applyHour(next);
  }

  void _pointerEnd(PointerEvent e) {
    final wasPinching = _pinching;
    _fingers.remove(e.pointer);
    if (_pinching && _fingers.length < 2) {
      setState(() => _pinching = false);
      widget.onZoom?.call(_hour);
      _hidePillSoon();
    }
    if (_fingers.isEmpty && wasPinching || _fingers.isEmpty && _quiet) {
      // After the tap callbacks of this very touch have run.
      Future.microtask(() => _quiet = false);
    }
  }

  /// Moves to [target] px per hour smoothly, keeping the middle of the screen still.
  void _glideTo(double target) {
    target = target.clamp(kHourMin, kHourMax);
    if ((target - _hour).abs() < 0.5) return;
    _focusY = _viewportHeight() / 2;
    _anchorHours =
        ((_vertical.hasClients ? _vertical.offset : 0) + _focusY) / _hour;
    _showPill();
    _hidePillSoon();
    if (MediaQuery.disableAnimationsOf(context)) {
      _applyHour(target);
      return;
    }
    final from = _hour;
    _glideTween?.removeListener(_onGlide);
    _glideTween = Tween<double>(begin: from, end: target).animate(
      CurvedAnimation(parent: _glide, curve: Curves.easeOutCubic),
    )..addListener(_onGlide);
    _glide
      ..reset()
      ..forward();
  }

  void _onGlide() {
    if (_glideTween != null) _applyHour(_glideTween!.value);
  }

  /// Taps are ignored while two fingers are down or right after they lift.
  VoidCallback _tap(VoidCallback f) =>
      () => (_pinching || _quiet) ? null : f();

  @override
  void initState() {
    super.initState();
    _glide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _glide.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() {});
    });
    _hBody.addListener(() => _link(_hBody, _hHead));
    _hHead.addListener(() => _link(_hHead, _hBody));
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && ShopTime.isSameDay(widget.date, ShopTime.today())) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToInterest());
  }

  @override
  void didUpdateWidget(covariant DayGrid old) {
    super.didUpdateWidget(old);
    // The zoom button (or a stored value) changed it from outside.
    if (widget.zoom != old.zoom && !_pinching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_pinching) _glideTo(widget.zoom);
      });
    }
    if (!ShopTime.isSameDay(old.date, widget.date)) {
      _mark = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToInterest());
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pillTimer?.cancel();
    _glide.dispose();
    _vertical.dispose();
    _hBody.dispose();
    _hHead.dispose();
    super.dispose();
  }

  void _link(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    _syncing = false;
  }

  bool get _isToday => ShopTime.isSameDay(widget.date, ShopTime.today());

  int? get _nowMin {
    if (!_isToday) return null;
    final n = ShopTime.now();
    return n.hour * 60 + n.minute;
  }

  bool _laneInView(int i, double laneW, double viewW) {
    final off = _hBody.hasClients ? _hBody.offset : 0.0;
    final left = i * laneW;
    return left + laneW > off - 4 && left < off + viewW - DayGrid.gutter + 4;
  }

  Widget? _header;
  Object? _headerFor;

  Widget _cachedHeader(double laneW, Widget Function() build) {
    final key = (widget.day, laneW, context.tokens);
    if (_header == null || _headerFor != key) {
      _headerFor = key;
      _header = build();
    }
    return _header!;
  }

  // The lanes' timelines and the hour range only change with the day, not with
  // the zoom, so a pinch (one rebuild per frame) does not recompute them.
  CalendarDay? _memoDay;
  Map<int, LaneTimeline>? _memoLines;
  ({int start, int end})? _memoRange;

  Map<int, LaneTimeline> _timelines() {
    if (!identical(_memoDay, widget.day) || _memoLines == null) {
      _memoDay = widget.day;
      _memoRange = null;
      _memoLines = {
        for (final l in widget.day.lanes)
          l.id: LaneTimeline.of(widget.day, l.id),
      };
    }
    return _memoLines!;
  }

  /// Hours shown: everyone's working span (or the shop hours), widened by any
  /// booking outside them.
  ({int start, int end}) _range(Map<int, LaneTimeline> lines) {
    return _memoRange ??= _computeRange(lines);
  }

  ({int start, int end}) _computeRange(Map<int, LaneTimeline> lines) {
    final a = widget.day.availability;
    int? lo;
    int? hi;
    for (final t in lines.values) {
      final s = t.span;
      if (s == null) continue;
      lo = lo == null || s.$1 < lo ? s.$1 : lo;
      hi = hi == null || s.$2 > hi ? s.$2 : hi;
    }
    var start = lo ?? a.openMin;
    var end = hi ?? a.closeMin;
    for (final e in widget.day.events) {
      if (e.startMin < start) start = e.startMin;
      if (e.endMin > end) end = e.endMin;
    }
    final s = (start ~/ 60).clamp(0, 22);
    final e = ((end + 59) ~/ 60).clamp(s + 6, 24);
    return (start: s, end: e);
  }

  void _scrollToInterest() {
    if (!_vertical.hasClients) return;
    final range = _range(_timelines());
    int? target;
    if (_isToday) {
      target = _nowMin! - 60;
    } else if (widget.day.events.isNotEmpty) {
      target =
          widget.day.events
              .map((e) => e.startMin)
              .reduce((a, b) => a < b ? a : b) -
          30;
    }
    final y = ((target ?? range.start * 60) - range.start * 60) / 60 * _hour;
    _vertical.jumpTo(y.clamp(0, _vertical.position.maxScrollExtent));
  }

  void _onLaneTap(
    CalendarLane lane,
    LaneTimeline line,
    double dy,
    ({int start, int end}) range,
  ) {
    final raw = range.start * 60 + dy / _hour * 60;
    // Rounded down to the quarter hour, like the web's click.
    final minute = (raw ~/ 15) * 15;
    final verdict = line.verdict(minute);
    if (verdict == SlotVerdict.free) {
      final room = (line.freeUntil(minute) ?? minute + 30) - minute;
      setState(() => _mark = _Mark(lane.id, minute, room.clamp(15, 30)));
      return;
    }
    setState(() => _mark = null);
    widget.onBlocked?.call(verdict, lane, minute);
  }

  @override
  Widget build(BuildContext context) {
    // The grid is drawn to the minute on fixed hour heights, so its text may only
    // grow a little (the rest of the app follows the phone's text size fully).
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.15)),
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final t = context.tokens;
    final lanes = widget.day.lanes;
    if (lanes.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_rounded,
        title: 'No barbers to show',
        message: 'There is no barber column for this calendar yet.',
      );
    }
    final lines = _timelines();
    final range = _range(lines);
    final hours = range.end - range.start;
    final gridHeight = hours * _hour;
    final now = _nowMin;
    // While the hours are zooming only the columns on screen are built (a frame
    // has to stay under 16 ms); at rest every column is there.
    final cull = _pinching || _glide.isAnimating;

    return LayoutBuilder(
      builder: (context, box) {
        final avail = box.maxWidth - DayGrid.gutter;
        final laneW = lanes.length == 1
            ? avail
            : (lanes.length == 2 ? avail / 2 : avail / 2.15);
        final bodyW = laneW * lanes.length;

        return Column(
          children: [
            // Pinned barber row (the same widget object across zoom frames, so it is
            // not rebuilt while pinching).
            _cachedHeader(
              laneW,
              () => SizedBox(
                height: DayGrid.headerHeight,
                child: Row(
                  children: [
                    const SizedBox(width: DayGrid.gutter),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _hHead,
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        child: SizedBox(
                          width: bodyW,
                          child: Row(
                            children: [
                              for (final l in lanes)
                                SizedBox(
                                  width: laneW,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onLongPress: () =>
                                        widget.onLaneLongPress?.call(l),
                                    child: _LaneHead(
                                      lane: l,
                                      line: lines[l.id]!,
                                      bookings: widget.day
                                          .forLane(l.id)
                                          .where((e) => !e.isBreak)
                                          .length,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: t.border),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Two fingers anywhere on the grid zoom the hours. It listens to
                  // the raw pointers (not the gesture arena), so scrolling, taps and
                  // long-press keep working with one finger exactly as before.
                  Listener(
                    key: _viewport,
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: _pointerDown,
                    onPointerMove: _pointerMove,
                    onPointerUp: _pointerEnd,
                    onPointerCancel: _pointerEnd,
                    child: SingleChildScrollView(
                      controller: _vertical,
                      physics: _pinching
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: widget.bottomPadding),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: DayGrid.gutter,
                              height: gridHeight,
                              child: _TimeAxis(
                                startHour: range.start,
                                endHour: range.end,
                                nowMinutes: now,
                                hour: _hour,
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _hBody,
                                scrollDirection: Axis.horizontal,
                                physics: _pinching
                                    ? const NeverScrollableScrollPhysics()
                                    : const ClampingScrollPhysics(),
                                child: SizedBox(
                                  width: bodyW,
                                  height: gridHeight,
                                  child: Stack(
                                    children: [
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: _GridPainter(
                                            startHour: range.start,
                                            endHour: range.end,
                                            lanes: lanes.length,
                                            line: t.border,
                                            faint: t.border.withValues(
                                              alpha: 0.45,
                                            ),
                                            hour: _hour,
                                          ),
                                        ),
                                      ),
                                      for (var i = 0; i < lanes.length; i++)
                                        if (!cull ||
                                            _laneInView(i, laneW, box.maxWidth))
                                          Positioned.fill(
                                            key: ValueKey(lanes[i].id),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                ..._background(
                                                  lanes[i],
                                                  lines[lanes[i].id]!,
                                                  i,
                                                  laneW,
                                                  range,
                                                  t,
                                                ),
                                                // Tap on empty column space.
                                                Positioned(
                                                  left: i * laneW,
                                                  width: laneW,
                                                  top: 0,
                                                  bottom: 0,
                                                  child: GestureDetector(
                                                    behavior: HitTestBehavior
                                                        .translucent,
                                                    onTapUp: (d) {
                                                      if (_pinching || _quiet) {
                                                        return;
                                                      }
                                                      _onLaneTap(
                                                        lanes[i],
                                                        lines[lanes[i].id]!,
                                                        d.localPosition.dy,
                                                        range,
                                                      );
                                                    },
                                                  ),
                                                ),
                                                if (_mark?.laneId ==
                                                    lanes[i].id)
                                                  _markWidget(
                                                    i,
                                                    laneW,
                                                    range,
                                                    t,
                                                  ),
                                                ..._laneEvents(
                                                  lanes[i],
                                                  i,
                                                  laneW,
                                                  range,
                                                ),
                                              ],
                                            ),
                                          ),
                                      if (now != null) _nowLine(range, t, now),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 10,
                    child: ZoomPill(
                      visible: _pill,
                      hour: _hour,
                      onReset: () {
                        widget.onZoom?.call(kHourDefault);
                        _glideTo(kHourDefault);
                      },
                    ),
                  ),
                  if (widget.showHint && !_pinching)
                    Positioned(
                      left: 14,
                      right: 14,
                      top: 8,
                      child: ZoomHint(onClose: () => widget.onHintSeen?.call()),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Free stretches (green), not-available stretches (hatched), the past (dimmed).
  List<Widget> _background(
    CalendarLane lane,
    LaneTimeline line,
    int index,
    double laneW,
    ({int start, int end}) range,
    AppTokens t,
  ) {
    final from = range.start * 60;
    final to = range.end * 60;
    double top(int m) => (m - from) / 60 * _hour;
    final out = <Widget>[];

    for (final (s, e) in line.unavailable(from, to)) {
      final h = top(e) - top(s);
      out.add(
        Positioned(
          left: index * laneW,
          width: laneW,
          top: top(s),
          height: h,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _HatchPainter(
                color: t.textMuted.withValues(alpha: t.isDark ? 0.2 : 0.24),
                fill: t.textMuted.withValues(alpha: t.isDark ? 0.07 : 0.08),
              ),
              child: h >= 54
                  ? Center(
                      child: _Caption(switch (line.state) {
                        LaneState.dayOff => 'Day off',
                        LaneState.noHours => 'No working hours set',
                        LaneState.shopClosed => 'Shop closed',
                        LaneState.open => 'Not available',
                      }, color: t.textMuted),
                    )
                  : null,
            ),
          ),
        ),
      );
    }

    for (final (s, e) in line.free) {
      final h = top(e) - top(s);
      out.add(
        Positioned(
          left: index * laneW + 2,
          width: laneW - 4,
          top: top(s) + 1,
          height: h - 2,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: t.success.withValues(alpha: t.isDark ? 0.09 : 0.11),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: t.success.withValues(alpha: t.isDark ? 0.22 : 0.3),
                ),
              ),
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.fromLTRB(7, 4, 6, 0),
              child: h >= 44
                  ? _Caption(
                      'Free · ${spanLabel(e - s)}',
                      color: t.success,
                      icon: Icons.add_rounded,
                    )
                  : null,
            ),
          ),
        ),
      );
    }

    // What is behind the clock is dimmed a little (today); it can still be booked.
    final now = _nowMin;
    if (now != null && now > from) {
      final pastTo = now.clamp(from, to);
      out.add(
        Positioned(
          left: index * laneW,
          width: laneW,
          top: 0,
          height: top(pastTo),
          child: IgnorePointer(
            child: ColoredBox(color: t.bg.withValues(alpha: 0.22)),
          ),
        ),
      );
    }
    return out;
  }

  Widget _markWidget(
    int index,
    double laneW,
    ({int start, int end}) range,
    AppTokens t,
  ) {
    final m = _mark!;
    final from = range.start * 60;
    return Positioned(
      left: index * laneW + 5,
      width: laneW - 10,
      top: (m.minute - from) / 60 * _hour,
      height: m.length / 60 * _hour,
      child: GestureDetector(
        onTap: _tap(() => widget.onSlotTap?.call(m.laneId, m.minute)),
        child: CustomPaint(
          painter: _DashedPainter(color: t.accent, radius: 10, width: 1.8),
          child: Container(
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_rounded, size: 18, color: t.accentText),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Book ${clockLabel(m.minute)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.bodyStrong.copyWith(
                      color: t.text,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _laneEvents(
    CalendarLane lane,
    int index,
    double laneW,
    ({int start, int end}) range,
  ) {
    final events = widget.day.forLane(lane.id)
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    // Side-by-side columns for bookings that overlap in the same lane.
    final cols = <int>[];
    final colEnds = <int>[];
    for (final e in events) {
      var c = colEnds.indexWhere((end) => end <= e.startMin);
      if (c == -1) {
        colEnds.add(e.endMin);
        c = colEnds.length - 1;
      } else {
        colEnds[c] = e.endMin;
      }
      cols.add(c);
    }
    final widths = <int>[];
    for (var i = 0; i < events.length; i++) {
      var maxCol = cols[i];
      for (var j = 0; j < events.length; j++) {
        final overlap =
            events[j].startMin < events[i].endMin &&
            events[i].startMin < events[j].endMin;
        if (overlap && cols[j] > maxCol) maxCol = cols[j];
      }
      widths.add(maxCol + 1);
    }
    final from = range.start * 60;
    return [
      for (var i = 0; i < events.length; i++)
        Positioned(
          left: index * laneW + (laneW / widths[i]) * cols[i] + 3,
          width: laneW / widths[i] - 6,
          top: (events[i].startMin - from) / 60 * _hour + 1,
          height: (events[i].duration / 60 * _hour - 3).clamp(
            30,
            double.infinity,
          ),
          child: events[i].isBreak
              ? _BreakCard(
                  event: events[i],
                  dim: widget.focus.isNotEmpty,
                  onTap: _tap(
                    () => widget.onBlocked?.call(
                      SlotVerdict.onBreak,
                      lane,
                      events[i].startMin,
                    ),
                  ),
                )
              : _ApptCard(
                  event: events[i],
                  dim:
                      widget.focus.isNotEmpty &&
                      !widget.focus.contains(events[i].status.code),
                  onTap: _tap(() => widget.onEventTap(events[i])),
                ),
        ),
    ];
  }

  Widget _nowLine(({int start, int end}) range, AppTokens t, int m) {
    if (m < range.start * 60 || m > range.end * 60) return const SizedBox();
    return Positioned(
      left: 0,
      right: 0,
      top: (m - range.start * 60) / 60 * _hour,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: t.danger,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(child: Container(height: 1.6, color: t.danger)),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text, {required this.color, this.icon});

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
      ],
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.label.copyWith(color: color, fontSize: 10.5),
        ),
      ),
    ],
  );
}

class _LaneHead extends StatelessWidget {
  const _LaneHead({
    required this.lane,
    required this.line,
    required this.bookings,
  });

  final CalendarLane lane;
  final LaneTimeline line;
  final int bookings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final freeMin = line.free.fold<int>(0, (a, r) => a + (r.$2 - r.$1));
    // Short enough for half a phone: whole hours, or minutes under an hour.
    final freeText = freeMin >= 60 ? '${freeMin ~/ 60}h' : '${freeMin}m';
    final (text, color) = switch (line.state) {
      LaneState.dayOff => ('Day off', t.warning),
      LaneState.noHours => ('No hours set', t.warning),
      LaneState.shopClosed => ('Shop closed', t.warning),
      LaneState.open =>
        bookings == 0
            ? ('Free · $freeText', t.success)
            : ('$bookings booked · $freeText free', t.textMuted),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppAvatar(name: lane.name, imageUrl: lane.photoUrl, size: 34),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lane.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(
                    color: t.text,
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(color: color, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeAxis extends StatelessWidget {
  const _TimeAxis({
    required this.startHour,
    required this.endHour,
    required this.nowMinutes,
    required this.hour,
  });

  final int startHour;
  final int endHour;
  final int? nowMinutes;

  /// Pixels per hour.
  final double hour;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var h = startHour; h < endHour; h++)
          Positioned(
            top: (h - startHour) * hour - 7,
            left: 0,
            right: 6,
            child: Text(
              h == startHour ? '' : _hourLabel(h),
              textAlign: TextAlign.right,
              style: AppType.caption.copyWith(
                color: t.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        if (nowMinutes != null &&
            nowMinutes! >= startHour * 60 &&
            nowMinutes! <= endHour * 60)
          Positioned(
            top: (nowMinutes! - startHour * 60) / 60 * hour - 9,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: t.danger,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                clockLabel(nowMinutes!).replaceAll(' ', ''),
                style: AppType.label.copyWith(
                  color: Colors.white,
                  fontSize: 9.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A booking, coloured by its status: pending = amber dashed, confirmed = blue,
/// rescheduled = violet, completed = green. The icon says it too, so colour
/// is never the only signal.
class _ApptCard extends StatelessWidget {
  const _ApptCard({
    required this.event,
    required this.onTap,
    required this.dim,
  });

  final CalendarEvent event;
  final VoidCallback onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.statusColor(event.status);
    final pending = event.status == AppointmentStatus.pending;
    final done = event.status == AppointmentStatus.completed;
    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: dim ? 0.3 : (done ? 0.78 : 1),
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        minSize: 0,
        child: LayoutBuilder(
          builder: (context, box) {
            final h = box.maxHeight;
            final tall = h >= 62;
            final lines = h >= 92;
            final range =
                '${clockLabel(event.startMin)} – ${clockLabel(event.endMin)}';
            return MediaQuery(
              // A short card cannot grow with the text size: it would cut itself off.
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: h < 62 ? TextScaler.noScaling : null),
              child: CustomPaint(
                foregroundPainter: pending
                    ? _DashedPainter(color: color, radius: 11, width: 1.8)
                    : null,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      color.withValues(alpha: t.isDark ? 0.34 : 0.24),
                      t.surface,
                    ),
                    borderRadius: BorderRadius.circular(11),
                    border: pending
                        ? null
                        : Border.all(color: color.withValues(alpha: 0.9)),
                  ),
                  child: Row(
                    children: [
                      Container(width: 5, color: color),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(7, 4, 6, 4),
                          // Zoomed out, a short booking is one line: time and name.
                          child: h < 38
                              ? Row(
                                  children: [
                                    Icon(
                                      event.status.icon,
                                      size: 14,
                                      color: color,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        '${clockLabel(event.startMin)}  ${event.title}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppType.bodyStrong.copyWith(
                                          color: t.text,
                                          fontSize: 12.5,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          event.status.icon,
                                          size: 14,
                                          color: color,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            tall
                                                ? range
                                                : clockLabel(event.startMin),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: AppType.label.copyWith(
                                              color: t.text,
                                              fontSize: 11,
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      event.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppType.bodyStrong.copyWith(
                                        color: t.text,
                                        fontSize: 13,
                                        height: 1.25,
                                      ),
                                    ),
                                    if (tall && event.serviceNames.isNotEmpty)
                                      Flexible(
                                        child: Text(
                                          event.serviceNames,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: lines ? 2 : 1,
                                          style: AppType.caption.copyWith(
                                            color: t.textSecondary,
                                            fontSize: 10.5,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    if (lines)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          event.status.label,
                                          style: AppType.label.copyWith(
                                            color: color,
                                            fontSize: 10.5,
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
          },
        ),
      ),
    );
  }
}

class _BreakCard extends StatelessWidget {
  const _BreakCard({
    required this.event,
    required this.onTap,
    required this.dim,
  });

  final CalendarEvent event;
  final VoidCallback onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AnimatedOpacity(
      duration: AppMotion.fast,
      opacity: dim ? 0.3 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: CustomPaint(
            painter: _HatchPainter(
              color: t.textMuted.withValues(alpha: 0.35),
              fill: t.textMuted.withValues(alpha: t.isDark ? 0.16 : 0.2),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: t.textMuted.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Icon(Icons.coffee_rounded, size: 15, color: t.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Break · ${clockLabel(event.startMin)} – ${clockLabel(event.endMin)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label.copyWith(
                        color: t.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.startHour,
    required this.endHour,
    required this.lanes,
    required this.line,
    required this.faint,
    required this.hour,
  });

  /// Pixels per hour: the half-hour dashes need room, the quarter-hour ones more.
  final double hour;
  final int startHour;
  final int endHour;
  final int lanes;
  final Color line;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    final hp = Paint()
      ..color = line
      ..strokeWidth = 1;
    final fp = Paint()
      ..color = faint
      ..strokeWidth = 1;
    for (var h = 0; h <= endHour - startHour; h++) {
      final y = h * hour;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hp);
      if (h < endHour - startHour) {
        // Half hours always (the tap rounds to quarters), quarter hours when roomy.
        for (final f in hour >= 120 ? [0.25, 0.5, 0.75] : [0.5]) {
          final dy = y + hour * f;
          final dash = f == 0.5 ? 4.0 : 2.0;
          for (var x = 0.0; x < size.width; x += 10) {
            canvas.drawLine(Offset(x, dy), Offset(x + dash, dy), fp);
          }
        }
      }
    }
    final lw = size.width / lanes;
    for (var i = 1; i < lanes; i++) {
      canvas.drawLine(Offset(lw * i, 0), Offset(lw * i, size.height), hp);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.hour != hour ||
      old.startHour != startHour ||
      old.endHour != endHour ||
      old.lanes != lanes ||
      old.line != line;
}

class _HatchPainter extends CustomPainter {
  _HatchPainter({required this.color, required this.fill});

  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fill);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) =>
      old.color != color || old.fill != fill;
}

/// A dashed rounded outline (pending bookings, the "Book" mark).
class _DashedPainter extends CustomPainter {
  _DashedPainter({
    required this.color,
    required this.radius,
    required this.width,
  });

  final Color color;
  final double radius;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(width / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()..addRRect(rrect);
    for (final PathMetric m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color || old.radius != radius || old.width != width;
}

/// "1.6x" while zooming; tap it to go back to 1x.
class ZoomPill extends StatelessWidget {
  const ZoomPill({
    super.key,
    required this.visible,
    required this.hour,
    required this.onReset,
    this.label,
  });

  final bool visible;

  /// Pixels per hour (the level is shown relative to 88).
  final double hour;

  /// Overrides the "1.8x" text (the landscape view measures against the whole day).
  final String? label;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final x = hour / kHourDefault;
    final text =
        label ??
        '${x.toStringAsFixed(x >= 1.95 || (x - 1).abs() < 0.04 ? 0 : 1)}x';
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: AppMotion.fast,
        opacity: visible ? 1 : 0,
        child: AnimatedScale(
          duration: AppMotion.fast,
          scale: visible ? 1 : 0.9,
          child: Pressable(
            onTap: onReset,
            minSize: 0,
            child: Semantics(
              button: true,
              label: 'Zoom $text. Double tap to reset.',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: t.surface.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: t.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in_rounded, size: 16, color: t.accentText),
                    const SizedBox(width: 5),
                    Text(
                      text,
                      style: AppType.label.copyWith(
                        color: t.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one-time tip: the zoom gesture cannot be seen, so it is said once.
class ZoomHint extends StatelessWidget {
  const ZoomHint({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.pinch_rounded, size: 22, color: t.accentText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pinch with two fingers to zoom the day',
              style: AppType.label.copyWith(color: t.text),
            ),
          ),
          Pressable(
            onTap: onClose,
            minSize: 40,
            child: Icon(Icons.close_rounded, size: 18, color: t.textMuted),
          ),
        ],
      ),
    );
  }
}
