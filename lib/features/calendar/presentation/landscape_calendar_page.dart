import 'dart:async';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/presentation/appointment_sheet.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/domain/day_timeline.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/day_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _laneW = 140.0;
const _axisH = 36.0;

/// The whole day on one wide screen: one row per barber, time running across.
/// Sideways the phone shows far more hours at once than a portrait column grid,
/// and every barber is on screen together, so who is free when can be read at a
/// glance. Opens full screen and turns the phone to landscape; closing it turns
/// it back. The forms (they need the keyboard) open in portrait.
class LandscapeCalendarPage extends ConsumerStatefulWidget {
  const LandscapeCalendarPage({super.key});

  @override
  ConsumerState<LandscapeCalendarPage> createState() =>
      _LandscapeCalendarPageState();
}

class _Mark {
  const _Mark(this.laneId, this.minute, this.length);

  final int laneId;
  final int minute;
  final int length;
}

class _LandscapeCalendarPageState extends ConsumerState<LandscapeCalendarPage> {
  final _vertical = ScrollController();
  final _hBody = ScrollController();
  final _hAxis = ScrollController();
  Timer? _tick;
  bool _syncing = false;
  // Detail first: names must be readable; the whole-day overview is one tap away.
  bool _zoomed = true;
  _Mark? _mark;
  String? _scrolledFor;

  // ---- pinch to zoom (time runs sideways here, so the fingers change px/hour)
  final _viewport = GlobalKey();
  final _fingers = <int, Offset>{};
  bool _pinching = false;

  /// Taps that end a pinch are not taps.
  bool _quiet = false;

  /// The remembered pinch value (null = the preset the top bar button picks).
  double? _custom;

  /// Live value while two fingers are down.
  double? _live;
  double _pphNow = 110; // what the last layout used
  double _fitNow = 58; // px/hour that fits the whole day: the lowest zoom
  int _hoursNow = 12;
  double _trackViewW = 600;
  double _startDist = 1;
  double _startPph = 110;
  double _anchorHours = 0;
  double _focusX = 0;
  bool _pill = false;
  Timer? _pillTimer;

  double get _lowest => _fitNow > kPphMin ? _fitNow : kPphMin;

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

  double _viewportLeft() {
    final box = _viewport.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.attached ? 0 : box.localToGlobal(Offset.zero).dx;
  }

  void _applyPph(double next) {
    final total = _hoursNow * next;
    final maxScroll = (total - _trackViewW).clamp(0.0, double.infinity);
    final target = (_anchorHours * next - _focusX).clamp(0.0, maxScroll);
    setState(() => _live = next);
    if (_hBody.hasClients) _hBody.jumpTo(target);
  }

  void _pointerDown(PointerDownEvent e) {
    _fingers[e.pointer] = e.position;
    if (_fingers.length != 2) return;
    final pts = _fingers.values.toList();
    _startDist = (pts[0] - pts[1]).distance.clamp(24, double.infinity);
    _startPph = _pphNow;
    // Where the fingers are over the hours (the pinned barber names are left of them).
    _focusX = (pts[0].dx + pts[1].dx) / 2 - _viewportLeft() - _laneW;
    _anchorHours =
        ((_hBody.hasClients ? _hBody.offset : 0) + _focusX) / _pphNow;
    _scrolledFor = '${ShopTime.ymd(ref.read(calendarDateProvider))}-c';
    _quiet = true;
    setState(() {
      _pinching = true;
      _mark = null;
    });
    _showPill();
  }

  void _pointerMove(PointerMoveEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    _fingers[e.pointer] = e.position;
    if (!_pinching || _fingers.length < 2) return;
    final pts = _fingers.values.take(2).toList();
    final next = (_startPph * (pts[0] - pts[1]).distance / _startDist).clamp(
      _lowest,
      kPphMax,
    );
    if ((next - _pphNow).abs() < 0.2) return;
    if ((next == _lowest || next == kPphMax) && _pphNow != next) {
      AppHaptics.select();
    }
    _applyPph(next);
  }

  void _pointerEnd(PointerEvent e) {
    _fingers.remove(e.pointer);
    if (_pinching && _fingers.length < 2) {
      final value = _live;
      if (value != null) ref.read(landscapeZoomProvider.notifier).set(value);
      setState(() {
        _pinching = false;
        _live = null;
      });
      _hidePillSoon();
    }
    if (_fingers.isEmpty && _quiet) {
      Future.microtask(() => _quiet = false);
    }
  }

  void _resetZoom() {
    ref.read(landscapeZoomProvider.notifier).set(null);
    setState(() {
      _live = null;
      _scrolledFor = null;
    });
    _showPill();
    _hidePillSoon();
  }

  static Future<void> _landscape() async {
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {
      // No platform channel (tests): nothing to turn.
    }
  }

  static Future<void> _portrait() async {
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      // No platform channel (tests).
    }
  }

  @override
  void initState() {
    super.initState();
    _landscape();
    _hBody.addListener(() => _link(_hBody, _hAxis));
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pillTimer?.cancel();
    _vertical.dispose();
    _hBody.dispose();
    _hAxis.dispose();
    _portrait();
    super.dispose();
  }

  void _link(ScrollController from, ScrollController to) {
    if (_syncing || !to.hasClients || !from.hasClients) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(0, to.position.maxScrollExtent));
    _syncing = false;
  }

  void _setMark(_Mark? m) => setState(() => _mark = m);

  void _goto(DateTime d) {
    setState(() => _mark = null);
    ref.read(calendarDateProvider.notifier).select(d);
    ref.read(calendarProvider.notifier).ensure(d);
  }

  Future<void> _pickDate(DateTime current) async {
    final today = ShopTime.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) _goto(picked);
  }

  /// Forms need the keyboard, which fills a landscape screen: they open in
  /// portrait and the day comes back in landscape afterwards.
  Future<void> _openForm(int laneId, int minute, DateTime date) async {
    final h = (minute ~/ 60).toString().padLeft(2, '0');
    final m = (minute % 60).toString().padLeft(2, '0');
    await _portrait();
    if (!mounted) return;
    await context.push(
      '/app/appointment/new?staff=$laneId&date=${ShopTime.ymd(date)}&time=$h:$m',
    );
    if (mounted) await _landscape();
  }

  Future<void> _addAppointment(DateTime date) async {
    await _portrait();
    if (!mounted) return;
    await context.push('/app/appointment/new?date=${ShopTime.ymd(date)}');
    if (mounted) await _landscape();
  }

  void _openBooking(CalendarEvent e) {
    if (e.appointmentId == null) return;
    showAppointmentSheet(
      context,
      laneStaffId: e.laneId,
      row: e.toAppointmentRow(
        ref.read(bootstrapProvider).actionsFor(e.status.code),
      ),
    );
  }

  /// Hours shown: everyone's working span (or the shop hours), widened by any
  /// booking outside them.
  ({int start, int end}) _range(CalendarDay day, Map<int, LaneTimeline> lines) {
    final a = day.availability;
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
    for (final e in day.events) {
      if (e.startMin < start) start = e.startMin;
      if (e.endMin > end) end = e.endMin;
    }
    final s = (start ~/ 60).clamp(0, 22);
    final e = ((end + 59) ~/ 60).clamp(s + 6, 24);
    return (start: s, end: e);
  }

  /// Scrolls sideways to what matters (now, or the first booking), once per
  /// day and zoom level.
  void _scrollToInterest(
    CalendarDay day,
    ({int start, int end}) range,
    double pph,
    DateTime date,
    bool pinched,
  ) {
    // A pinched zoom keeps its own key: its value changes all the time and must
    // not throw the view back to "now".
    final key = pinched
        ? '${ShopTime.ymd(date)}-c'
        : '${ShopTime.ymd(date)}-$_zoomed-${pph.round()}';
    if (_scrolledFor == key) return;
    _scrolledFor = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hBody.hasClients) return;
      int? target;
      if (ShopTime.isSameDay(date, ShopTime.today())) {
        final n = ShopTime.now();
        target = n.hour * 60 + n.minute - 90;
      } else if (day.events.isNotEmpty) {
        target =
            day.events.map((e) => e.startMin).reduce((a, b) => a < b ? a : b) -
            30;
      }
      final x = ((target ?? range.start * 60) - range.start * 60) / 60 * pph;
      _hBody.jumpTo(x.clamp(0, _hBody.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mq = MediaQuery.of(context);
    final date = ref.watch(calendarDateProvider);
    final window = ref.watch(calendarProvider);
    _custom = ref.watch(landscapeZoomProvider);

    // The phone is still turning: do not lay the wide view out in portrait.
    if (mq.orientation == Orientation.portrait) {
      return Scaffold(
        backgroundColor: t.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    Widget body;
    if (window.value == null) {
      body = window.hasError
          ? ErrorState(
              message: window.error is Failure
                  ? (window.error! as Failure).userMessage
                  : 'Could not load the calendar.',
              onRetry: () => ref.invalidate(calendarProvider),
            )
          : const Center(child: CircularProgressIndicator());
    } else {
      final avail =
          ref.watch(dayAvailabilityProvider(ShopTime.ymd(date))).value ??
          DayAvailability.fallback();
      final day = window.value!.day(
        date,
        avail,
        onlyStaffId: ref.watch(calendarStaffFilterProvider),
        order: ref.watch(calendarOrderProvider),
      );
      body = _Day(state: this, day: day, date: date);
    }

    return MediaQuery(
      // The drawing is laid out to the minute: text may only grow a little.
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.15)),
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                date: date,
                counts: window.value == null
                    ? null
                    : DayCounts.of(
                        window.value!.day(
                          date,
                          DayAvailability.fallback(),
                          onlyStaffId: ref.watch(calendarStaffFilterProvider),
                        ),
                      ),
                zoomed: _zoomed,
                onClose: () => context.pop(),
                onPrev: () => _goto(date.subtract(const Duration(days: 1))),
                onNext: () => _goto(date.add(const Duration(days: 1))),
                onToday: () => _goto(ShopTime.today()),
                onPick: () => _pickDate(date),
                onZoom: () {
                  // The two presets: the whole day, or more detail (a pinch is forgotten).
                  ref.read(landscapeZoomProvider.notifier).set(null);
                  setState(() {
                    _live = null;
                    _zoomed = !_zoomed;
                  });
                },
                onAdd: () => _addAppointment(date),
              ),
              Divider(height: 1, color: t.border),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

/// The wide day: lane names pinned on the left, hours pinned on top.
class _Day extends StatelessWidget {
  const _Day({required this.state, required this.day, required this.date});

  final _LandscapeCalendarPageState state;
  final CalendarDay day;
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lanes = day.lanes;
    if (lanes.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_rounded,
        title: 'No barbers to show',
        message: 'There is no barber row for this calendar yet.',
      );
    }
    final lines = {for (final l in lanes) l.id: LaneTimeline.of(day, l.id)};
    final range = state._range(day, lines);
    final hours = range.end - range.start;
    final isToday = ShopTime.isSameDay(date, ShopTime.today());
    final n = ShopTime.now();
    final nowMin = isToday ? n.hour * 60 + n.minute : null;

    return LayoutBuilder(
      builder: (context, box) {
        final trackViewW = box.maxWidth - _laneW;
        // Fit the whole day when that is still readable, else scroll sideways.
        final fit = trackViewW / hours;
        final preset = state._zoomed
            ? (fit * 1.8).clamp(110.0, 190.0)
            : (fit < 58 ? 58.0 : fit);
        // A pinch (live, then remembered) wins over the preset; never below the
        // whole day, so the hours always fill the width.
        final custom = state._live ?? state._custom;
        final pph = custom == null
            ? preset
            : custom.clamp(fit > kPphMin ? fit : kPphMin, kPphMax);
        state
          .._fitNow = fit
          .._hoursNow = hours
          .._trackViewW = trackViewW
          .._pphNow = pph;
        final totalW = hours * pph;
        final rowH = ((box.maxHeight - _axisH - 1) / lanes.length).clamp(
          60.0,
          120.0,
        );
        if (state._live == null) {
          state._scrollToInterest(day, range, pph, date, custom != null);
        }

        double x(int minute) => (minute - range.start * 60) / 60 * pph;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Two fingers anywhere zoom the hours (raw pointers, so the scrolls, taps
            // and the pinned names keep working with one finger).
            Listener(
              key: state._viewport,
              behavior: HitTestBehavior.translucent,
              onPointerDown: state._pointerDown,
              onPointerMove: state._pointerMove,
              onPointerUp: state._pointerEnd,
              onPointerCancel: state._pointerEnd,
              child: Column(
                children: [
                  SizedBox(
                    height: _axisH,
                    child: Row(
                      children: [
                        SizedBox(
                          width: _laneW,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'BARBER',
                                style: AppType.overline.copyWith(
                                  color: t.textMuted,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: state._hAxis,
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            child: _Axis(
                              startHour: range.start,
                              endHour: range.end,
                              pph: pph,
                              nowMin: nowMin,
                              x: x,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: t.border),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: state._vertical,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              for (final l in lanes)
                                _LaneHead(
                                  lane: l,
                                  line: lines[l.id]!,
                                  booked: day
                                      .forLane(l.id)
                                      .where((e) => !e.isBreak)
                                      .length,
                                  height: rowH,
                                ),
                            ],
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              controller: state._hBody,
                              scrollDirection: Axis.horizontal,
                              physics: state._pinching
                                  ? const NeverScrollableScrollPhysics()
                                  : const ClampingScrollPhysics(),
                              child: SizedBox(
                                width: totalW,
                                height: rowH * lanes.length,
                                child: Stack(
                                  children: [
                                    Column(
                                      children: [
                                        for (final l in lanes)
                                          _Track(
                                            lane: l,
                                            line: lines[l.id]!,
                                            events: day.forLane(l.id),
                                            startMin: range.start * 60,
                                            endMin: range.end * 60,
                                            pph: pph,
                                            height: rowH,
                                            nowMin: nowMin,
                                            mark: state._mark?.laneId == l.id
                                                ? state._mark
                                                : null,
                                            onBooking: (e) {
                                              if (state._pinching ||
                                                  state._quiet) {
                                                return;
                                              }
                                              state._openBooking(e);
                                            },
                                            view: state._pinching
                                                ? (
                                                    from:
                                                        (state._hBody.hasClients
                                                            ? state
                                                                  ._hBody
                                                                  .offset
                                                            : 0.0) -
                                                        80,
                                                    to:
                                                        (state._hBody.hasClients
                                                            ? state
                                                                  ._hBody
                                                                  .offset
                                                            : 0.0) +
                                                        trackViewW +
                                                        80,
                                                  )
                                                : null,
                                            onTapLane: (dx) =>
                                                state._pinching || state._quiet
                                                ? null
                                                : _onLaneTap(
                                                    context,
                                                    l,
                                                    lines[l.id]!,
                                                    dx,
                                                    range,
                                                    pph,
                                                  ),
                                            onMark: () {
                                              final m = state._mark;
                                              if (m != null) {
                                                state._openForm(
                                                  m.laneId,
                                                  m.minute,
                                                  date,
                                                );
                                              }
                                            },
                                          ),
                                      ],
                                    ),
                                    if (nowMin != null &&
                                        nowMin >= range.start * 60 &&
                                        nowMin <= range.end * 60)
                                      Positioned(
                                        left: x(nowMin) - 1,
                                        top: 0,
                                        bottom: 0,
                                        width: 2,
                                        child: IgnorePointer(
                                          child: ColoredBox(color: t.danger),
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
                ],
              ),
            ),
            Positioned(
              top: _axisH + 8,
              right: 10,
              child: ZoomPill(
                visible: state._pill,
                hour: pph,
                label: '${(pph / fit).toStringAsFixed(1)}x',
                onReset: state._resetZoom,
              ),
            ),
          ],
        );
      },
    );
  }

  void _onLaneTap(
    BuildContext context,
    CalendarLane lane,
    LaneTimeline line,
    double dx,
    ({int start, int end}) range,
    double pph,
  ) {
    final raw = range.start * 60 + dx / pph * 60;
    // Rounded down to the quarter hour, like the web's click.
    final minute = (raw ~/ 15) * 15;
    final verdict = line.verdict(minute);
    if (verdict == SlotVerdict.free) {
      final room = (line.freeUntil(minute) ?? minute + 30) - minute;
      state._setMark(_Mark(lane.id, minute, room.clamp(15, 30)));
      return;
    }
    state._setMark(null);
    showToast(
      context,
      slotBlockedMessage(verdict, lane, minute),
      kind: ToastKind.info,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.date,
    required this.counts,
    required this.zoomed,
    required this.onClose,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onPick,
    required this.onZoom,
    required this.onAdd,
  });

  final DateTime date;
  final DayCounts? counts;
  final bool zoomed;
  final VoidCallback onClose;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final VoidCallback onPick;
  final VoidCallback onZoom;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final isToday = ShopTime.isSameDay(date, ShopTime.today());
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _BarButton(
              icon: Icons.close_rounded,
              label: 'Close landscape view',
              onTap: onClose,
            ),
            const SizedBox(width: 4),
            _BarButton(
              icon: Icons.chevron_left_rounded,
              label: 'Previous day',
              onTap: onPrev,
            ),
            Pressable(
              onTap: onPick,
              minSize: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ShopTime.weekdayLong(date).toUpperCase(),
                      style: AppType.overline.copyWith(
                        color: t.accentText,
                        fontSize: 10,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ShopTime.dayLabel(date),
                          style: AppText.display(
                            18,
                            color: t.text,
                            height: 1.1,
                          ),
                        ),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: t.accentText,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _BarButton(
              icon: Icons.chevron_right_rounded,
              label: 'Next day',
              onTap: onNext,
            ),
            if (!isToday) ...[
              const SizedBox(width: 4),
              Pressable(
                onTap: onToday,
                minSize: 0,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: t.border),
                  ),
                  child: Text(
                    'Today',
                    style: AppType.label.copyWith(color: t.text, fontSize: 13),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: counts == null
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in const [
                            AppointmentStatus.pending,
                            AppointmentStatus.confirmed,
                            AppointmentStatus.rescheduled,
                            AppointmentStatus.completed,
                          ])
                            if (s != AppointmentStatus.completed ||
                                counts!.of(s.code) > 0)
                              _LegendDot(status: s, count: counts!.of(s.code)),
                        ],
                      ),
                    ),
            ),
            _BarButton(
              icon: zoomed
                  ? Icons.zoom_out_map_rounded
                  : Icons.zoom_in_map_rounded,
              label: zoomed ? 'Show the whole day' : 'Show more detail',
              onTap: onZoom,
            ),
            const SizedBox(width: 4),
            _BarButton(
              icon: Icons.add_rounded,
              label: 'Add Appointment',
              onTap: onAdd,
              filled: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        minSize: 0,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? t.accent : t.surface,
            border: filled ? null : Border.all(color: t.border),
          ),
          child: Icon(icon, size: 22, color: filled ? t.onAccent : t.text),
        ),
      ),
    );
  }
}

String _word(AppointmentStatus s) => switch (s) {
  AppointmentStatus.pending => 'Pending',
  AppointmentStatus.confirmed => 'Confirmed',
  AppointmentStatus.rescheduled => 'Rescheduled',
  AppointmentStatus.completed => 'Completed',
  AppointmentStatus.cancelled => 'Cancelled',
};

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.status, required this.count});

  final AppointmentStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.statusColor(status);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(
            '${_word(status)} $count',
            style: AppType.caption.copyWith(
              color: count == 0 ? t.textMuted : t.textSecondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The hours across the top, with the time now pinned on it.
class _Axis extends StatelessWidget {
  const _Axis({
    required this.startHour,
    required this.endHour,
    required this.pph,
    required this.nowMin,
    required this.x,
  });

  final int startHour;
  final int endHour;
  final double pph;
  final int? nowMin;
  final double Function(int minute) x;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final w = (endHour - startHour) * pph;
    final showNow =
        nowMin != null && nowMin! >= startHour * 60 && nowMin! <= endHour * 60;
    return SizedBox(
      width: w,
      height: _axisH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var h = startHour; h < endHour; h++)
            Positioned(
              left: (h - startHour) * pph,
              top: 0,
              bottom: 0,
              width: pph,
              child: Container(
                alignment: Alignment.topLeft,
                padding: const EdgeInsets.only(left: 6, top: 3),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: t.border)),
                ),
                child: Text(
                  _hour(h),
                  maxLines: 1,
                  style: AppType.caption.copyWith(
                    color: t.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          if (showNow)
            Positioned(
              left: x(nowMin!) - 30,
              width: 60,
              bottom: 2,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: t.danger,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    clockLabel(nowMin!),
                    maxLines: 1,
                    style: AppType.caption.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _hour(int h) {
    final h24 = h % 24;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12 ${h24 < 12 ? 'AM' : 'PM'}';
  }
}

class _LaneHead extends StatelessWidget {
  const _LaneHead({
    required this.lane,
    required this.line,
    required this.booked,
    required this.height,
  });

  final CalendarLane lane;
  final LaneTimeline line;
  final int booked;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final free = line.free.fold<int>(0, (s, r) => s + (r.$2 - r.$1));
    final sub = switch (line.state) {
      LaneState.dayOff => 'Day off',
      LaneState.noHours => 'No hours set',
      LaneState.shopClosed => 'Shop closed',
      LaneState.open =>
        booked == 0
            ? 'Free · ${spanLabel(free)}'
            : '$booked booked · ${spanLabel(free)} free',
    };
    return Container(
      width: _laneW,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(
          right: BorderSide(color: t.border),
          bottom: BorderSide(color: t.border),
        ),
      ),
      child: Row(
        children: [
          AppAvatar(name: lane.name, imageUrl: lane.photoUrl, size: 30),
          const SizedBox(width: 8),
          Expanded(
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
                    fontSize: 13,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: line.isOpen && booked == 0 ? t.success : t.textMuted,
                    fontSize: 10.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One barber's day as a row: working time, what cannot be booked, the
/// bookings and breaks, free time that can be tapped.
class _Track extends StatelessWidget {
  const _Track({
    required this.lane,
    required this.line,
    required this.events,
    required this.startMin,
    required this.endMin,
    required this.pph,
    required this.height,
    required this.nowMin,
    required this.mark,
    required this.onBooking,
    required this.onTapLane,
    required this.onMark,
    this.view,
  });

  final CalendarLane lane;
  final LaneTimeline line;
  final List<CalendarEvent> events;
  final int startMin;
  final int endMin;
  final double pph;
  final double height;
  final int? nowMin;
  final _Mark? mark;
  final void Function(CalendarEvent event) onBooking;
  final void Function(double dx) onTapLane;
  final VoidCallback onMark;

  /// While the hours zoom, only blocks inside this horizontal window are built.
  final ({double from, double to})? view;

  bool _in(double left, double width) =>
      view == null || (left + width > view!.from && left < view!.to);

  double _x(int m) => (m - startMin) / 60 * pph;

  double _breakW(CalendarEvent e) =>
      ((e.endMin - e.startMin) / 60 * pph).clamp(18.0, 4000);

  double _bookW(CalendarEvent e) =>
      (((e.endMin <= e.startMin ? e.startMin + 15 : e.endMin) - e.startMin) /
                  60 *
                  pph -
              2)
          .clamp(22.0, 4000);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final caption = switch (line.state) {
      LaneState.dayOff => 'Day off',
      LaneState.noHours => 'No working hours set',
      LaneState.shopClosed => 'Shop closed',
      LaneState.open => null,
    };
    return SizedBox(
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) => onTapLane(d.localPosition.dx),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _TrackPainter(
                    startMin: startMin,
                    endMin: endMin,
                    pph: pph,
                    free: line.free,
                    unavailable: line.unavailable(startMin, endMin),
                    line: t.border,
                    faint: t.border.withValues(alpha: 0.4),
                    green: t.success,
                    hatch: t.textMuted.withValues(alpha: t.isDark ? 0.2 : 0.26),
                    hatchFill: t.textMuted.withValues(
                      alpha: t.isDark ? 0.07 : 0.09,
                    ),
                    surface: t.surface,
                  ),
                ),
              ),
            ),
            if (caption != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        caption,
                        style: AppType.label.copyWith(
                          color: t.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            for (final (s, e) in line.free)
              if ((e - s) / 60 * pph >= 88)
                Positioned(
                  left: _x(s) + 8,
                  top: 6,
                  child: IgnorePointer(
                    child: Text(
                      'Free · ${spanLabel(e - s)}',
                      style: AppType.caption.copyWith(
                        color: t.success,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            for (final e in events)
              if (e.isBreak && _in(_x(e.startMin), _breakW(e)))
                Positioned(
                  key: ValueKey(e.id),
                  left: _x(e.startMin),
                  width: _breakW(e),
                  top: 8,
                  bottom: 8,
                  child: _BreakBlock(event: e),
                ),
            for (final e in events)
              if (!e.isBreak && _in(_x(e.startMin), _bookW(e)))
                Positioned(
                  key: ValueKey(e.id),
                  left: _x(e.startMin) + 1,
                  width: _bookW(e),
                  top: 7,
                  bottom: 7,
                  child: _BookingBlock(
                    event: e,
                    live:
                        nowMin != null &&
                        nowMin! >= e.startMin &&
                        nowMin! < e.endMin,
                    onTap: () => onBooking(e),
                  ),
                ),
            if (mark != null)
              Positioned(
                left: _x(mark!.minute),
                width: (mark!.length / 60 * pph).clamp(96.0, 4000),
                top: 9,
                bottom: 9,
                child: Pressable(
                  onTap: onMark,
                  minSize: 0,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.accent, width: 1.6),
                    ),
                    child: Text(
                      'Book ${clockLabel(mark!.minute)}',
                      maxLines: 1,
                      style: AppType.label.copyWith(
                        color: t.accentText,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookingBlock extends StatelessWidget {
  const _BookingBlock({
    required this.event,
    required this.live,
    required this.onTap,
  });

  final CalendarEvent event;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.statusColor(event.status);
    final end = event.endMin <= event.startMin
        ? event.startMin + 15
        : event.endMin;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return Semantics(
          button: true,
          label:
              '${event.title}, ${clockLabel(event.startMin)} to ${clockLabel(end)}, ${event.status.label}. Opens details.',
          excludeSemantics: true,
          child: Pressable(
            onTap: onTap,
            scale: 0.98,
            minSize: 0,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  color.withValues(alpha: t.isDark ? 0.34 : 0.24),
                  t.surface,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: live ? t.danger : color.withValues(alpha: 0.9),
                  width: live ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(width: 4, color: color),
                  Expanded(
                    child: w < 54
                        ? Center(
                            child: Icon(
                              event.status.icon,
                              size: 14,
                              color: color,
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(6, 3, 4, 3),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  event.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.bodyStrong.copyWith(
                                    color: t.text,
                                    fontSize: 12.5,
                                  ),
                                ),
                                if (w >= 96)
                                  Row(
                                    children: [
                                      Icon(
                                        event.status.icon,
                                        size: 11,
                                        color: color,
                                      ),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          clockRange(event.startMin, end),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppType.caption.copyWith(
                                            color: t.textSecondary,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ),
                                    ],
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
    );
  }
}

class _BreakBlock extends StatelessWidget {
  const _BreakBlock({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.textMuted.withValues(alpha: t.isDark ? 0.22 : 0.2),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.textMuted.withValues(alpha: 0.5)),
      ),
      child: Icon(Icons.coffee_rounded, size: 15, color: t.textSecondary),
    );
  }
}

/// "10:15 – 11:00 AM".
String clockRange(int start, int end) {
  final a = clockLabel(start);
  final b = clockLabel(end);
  final same = a.substring(a.length - 2) == b.substring(b.length - 2);
  return same ? '${a.substring(0, a.length - 3)} – $b' : '$a – $b';
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.startMin,
    required this.endMin,
    required this.pph,
    required this.free,
    required this.unavailable,
    required this.line,
    required this.faint,
    required this.green,
    required this.hatch,
    required this.hatchFill,
    required this.surface,
  });

  final int startMin;
  final int endMin;
  final double pph;
  final List<(int, int)> free;
  final List<(int, int)> unavailable;
  final Color line;
  final Color faint;
  final Color green;
  final Color hatch;
  final Color hatchFill;
  final Color surface;

  double _x(int m) => (m - startMin) / 60 * pph;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = surface);
    // Free working time: soft green.
    final fill = Paint()..color = green.withValues(alpha: 0.12);
    final edge = Paint()
      ..color = green.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke;
    for (final (s, e) in free) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTRB(_x(s), 3, _x(e), size.height - 3),
        const Radius.circular(8),
      );
      canvas.drawRRect(r, fill);
      canvas.drawRRect(r, edge);
    }
    // Not available: hatched.
    final hp = Paint()
      ..color = hatch
      ..strokeWidth = 1;
    for (final (s, e) in unavailable) {
      final r = Rect.fromLTRB(_x(s), 0, _x(e), size.height);
      canvas.drawRect(r, Paint()..color = hatchFill);
      canvas.save();
      canvas.clipRect(r);
      for (var x = r.left - size.height; x < r.right; x += 12) {
        canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), hp);
      }
      canvas.restore();
    }
    // Hour lines (and the half hours, fainter).
    final strong = Paint()
      ..color = line
      ..strokeWidth = 1;
    final soft = Paint()
      ..color = faint
      ..strokeWidth = 1;
    for (var m = startMin; m <= endMin; m += 30) {
      final x = _x(m);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        m % 60 == 0 ? strong : soft,
      );
    }
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      strong,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.pph != pph ||
      old.startMin != startMin ||
      old.endMin != endMin ||
      old.free != free ||
      old.unavailable != unavailable ||
      old.surface != surface ||
      old.line != line;
}
