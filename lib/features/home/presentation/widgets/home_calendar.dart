import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/domain/day_timeline.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/day_grid.dart';
import 'package:flutter/material.dart';

/// Home's "Staff Calendar" block: the shop floor right now, in plain words.
///
/// Three numbers (with a client / free / not in), the time and the shop hours,
/// then one calm row per barber who works today: who, what they do now, and
/// their day as one thin bar. Tap a row for that day in a sheet (bookings,
/// breaks and free time in order, a red NOW line); a booking opens its details,
/// a free time starts a booking at that time, and the green plus on a free
/// barber books them right now.
class StaffCalendarCard extends StatelessWidget {
  const StaffCalendarCard({
    super.key,
    required this.day,
    required this.onBooking,
    required this.onFree,
  });

  final CalendarDay day;

  /// A booking card was tapped.
  final void Function(CalendarEvent event) onBooking;

  /// A free time was tapped: book this barber at [minute].
  final void Function(CalendarLane lane, int minute) onFree;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = day.availability;
    final n = ShopTime.now();
    final nowMin = n.hour * 60 + n.minute;

    final rows = <_Row>[];
    final away = <_Row>[];
    for (final lane in day.lanes) {
      final line = LaneTimeline.of(day, lane.id);
      final events = day.forLane(lane.id);
      final bookings = [
        for (final e in events)
          if (!e.isBreak) e,
      ];
      final now = LaneNow.of(line, bookings, nowMin);
      final row = _Row(lane, line, events, bookings, now);
      (now.presence == Presence.off ? away : rows).add(row);
    }

    int count(bool Function(Presence) test) =>
        [...rows, ...away].where((r) => test(r.now.presence)).length;
    final busy = count((p) => p == Presence.busy || p == Presence.onBreak);
    final free = count((p) => p == Presence.free);
    final gone = day.lanes.length - busy - free;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ShopLine(availability: a, nowMin: nowMin),
          const SizedBox(height: AppSpace.md),
          _Counters(busy: busy, free: free, gone: gone),
          if (rows.isEmpty) ...[
            const SizedBox(height: AppSpace.md),
            _Banner(
              icon: Icons.bedtime_rounded,
              text: 'Nobody is working today.',
              color: t.textSecondary,
            ),
          ] else
            _Lanes(
              rows: rows,
              nowMin: nowMin,
              onBooking: onBooking,
              onFree: onFree,
            ),
          if (away.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            _AwayGroup(rows: away),
          ],
        ],
      ),
    );
  }
}

/// The barbers who work today, four open and the rest one tap away. Each is one
/// calm row; the day of a barber opens in a sheet when the row is tapped.
class _Lanes extends StatefulWidget {
  const _Lanes({
    required this.rows,
    required this.nowMin,
    required this.onBooking,
    required this.onFree,
  });

  final List<_Row> rows;
  final int nowMin;
  final void Function(CalendarEvent event) onBooking;
  final void Function(CalendarLane lane, int minute) onFree;

  @override
  State<_Lanes> createState() => _LanesState();
}

class _LanesState extends State<_Lanes> {
  static const _limit = 4;
  bool _all = false;

  /// Bookings start on the quarter hour.
  static int _roundUp(int m) => (m + 14) ~/ 15 * 15;

  void _openDay(_Row row) {
    showAppSheet<void>(
      context,
      title: row.lane.name,
      builder: (sheet) => _DayList(
        row: row,
        nowMin: widget.nowMin,
        // The booking or the form opens on top of the page, so the sheet goes first.
        onBooking: (e) {
          Navigator.of(sheet).pop();
          widget.onBooking(e);
        },
        onFree: (lane, minute) {
          Navigator.of(sheet).pop();
          widget.onFree(lane, minute);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = _all ? widget.rows : widget.rows.take(_limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in shown) ...[
          const SizedBox(height: AppSpace.sm + 2),
          _LaneRow(
            row: r,
            nowMin: widget.nowMin,
            onOpen: () => _openDay(r),
            onBook: () => widget.onFree(r.lane, _roundUp(widget.nowMin)),
          ),
        ],
        if (widget.rows.length > _limit)
          Pressable(
            onTap: () => setState(() => _all = !_all),
            minSize: 0,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Center(
                child: Text(
                  _all
                      ? 'Show fewer barbers'
                      : 'Show ${widget.rows.length - _limit} more ${widget.rows.length - _limit == 1 ? 'barber' : 'barbers'}',
                  style: AppType.label.copyWith(
                    color: t.accentText,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// How wide a booking, break or free card is when they sit side by side.
const _cardWidth = 148.0;

/// "10:15 – 11:00 AM" (one AM/PM when both are the same), "11:30 AM – 1:00 PM".
String _range(int start, int end) {
  final a = clockLabel(start);
  final b = clockLabel(end);
  final sameHalf = a.substring(a.length - 2) == b.substring(b.length - 2);
  return sameHalf ? '${a.substring(0, a.length - 3)} – $b' : '$a – $b';
}

class _Row {
  const _Row(this.lane, this.line, this.events, this.bookings, this.now);

  final CalendarLane lane;
  final LaneTimeline line;
  final List<CalendarEvent> events;
  final List<CalendarEvent> bookings;
  final LaneNow now;
}

Color _presenceColor(AppTokens t, Presence p) => switch (p) {
  Presence.busy => t.danger,
  Presence.onBreak => t.warning,
  Presence.free => t.success,
  Presence.later || Presence.done || Presence.off => t.textMuted,
};

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: AppType.label.copyWith(color: t.text, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// The time now and what the shop is doing: "NOW 2:24 PM · Open until 8 PM".
class _ShopLine extends StatelessWidget {
  const _ShopLine({required this.availability, required this.nowMin});

  final DayAvailability availability;
  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = availability;
    final (String text, Color color, IconData icon) = a.shopDayOff
        ? ('Shop is closed today', t.warning, Icons.event_busy_rounded)
        : !a.known
        ? ('', t.textMuted, Icons.schedule_rounded)
        : nowMin < a.openMin
        ? (
            'Opens at ${clockLabel(a.openMin)}',
            t.textSecondary,
            Icons.storefront_rounded,
          )
        : nowMin >= a.closeMin
        ? (
            'Closed since ${clockLabel(a.closeMin)}',
            t.textSecondary,
            Icons.storefront_rounded,
          )
        : (
            'Open until ${clockLabel(a.closeMin)}',
            t.success,
            Icons.storefront_rounded,
          );
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(4, 2, 10, 2),
          decoration: BoxDecoration(
            color: t.danger,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A soft ring pulses from the dot: this is live.
              const PulseDot(color: Colors.white, size: 6),
              Text(
                'NOW ${clockLabel(nowMin)}',
                style: AppType.caption.copyWith(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 10),
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.label.copyWith(
                color: t.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "1 with client / 2 free now / 2 not in": the whole floor as three chips.
class _Counters extends StatelessWidget {
  const _Counters({required this.busy, required this.free, required this.gone});

  final int busy;
  final int free;
  final int gone;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget chip(int n, String label, Color color) => Semantics(
      label: '$n $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: n == 0
              ? t.border.withValues(alpha: 0.3)
              : color.withValues(alpha: t.isDark ? 0.16 : 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: n == 0 ? t.border : color.withValues(alpha: 0.4),
          ),
        ),
        // Shrinks a little instead of wrapping, so the three stay on one line.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: n == 0 ? t.textMuted : color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$n',
                style: AppType.title.copyWith(
                  color: n == 0 ? t.textMuted : t.text,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppType.caption.copyWith(
                  color: t.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Row(
      children: [
        Expanded(child: chip(busy, 'with client', t.danger)),
        const SizedBox(width: 5),
        Expanded(child: chip(free, 'free now', t.success)),
        const SizedBox(width: 5),
        Expanded(child: chip(gone, 'not in', t.textMuted)),
      ],
    );
  }
}

/// One barber as one row: who they are, what they do now, and their day as a
/// thin bar (green = free, coloured = booked, a red tick = now). Tap the row for
/// the whole day; the green plus books a free barber right now.
class _LaneRow extends StatelessWidget {
  const _LaneRow({
    required this.row,
    required this.nowMin,
    required this.onOpen,
    required this.onBook,
  });

  final _Row row;
  final int nowMin;
  final VoidCallback onOpen;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final now = row.now;
    final color = _presenceColor(t, now.presence);
    final (String words, IconData icon) = _presenceWords(now);
    final String? when = _presenceWhen(now);
    final booked = row.bookings.length;
    final canBook = now.presence == Presence.free;

    return Semantics(
      button: true,
      label:
          '${row.lane.name}. $words${when == null ? '' : ', $when'}. $booked booked.${now.noHours ? ' No working hours set for today.' : ''} Opens the day.',
      excludeSemantics: true,
      child: Pressable(
        onTap: onOpen,
        scale: 0.985,
        minSize: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 10),
          decoration: BoxDecoration(
            color: t.border.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.border.withValues(alpha: 0.7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AppAvatar(
                        name: row.lane.name,
                        imageUrl: row.lane.photoUrl,
                        size: 38,
                      ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: t.surface, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.lane.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.bodyStrong.copyWith(
                            color: t.text,
                            fontSize: 15,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(icon, size: 13, color: color),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                now.noHours ? '$words · no hours' : words,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.label.copyWith(
                                  color: now.presence == Presence.free
                                      ? t.success
                                      : t.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (when != null)
                        Text(
                          when,
                          style: AppType.label.copyWith(
                            color: t.text,
                            fontSize: 12.5,
                          ),
                        ),
                      Text(
                        booked == 0
                            ? 'No bookings'
                            : '$booked ${booked == 1 ? 'booking' : 'bookings'}',
                        style: AppType.caption.copyWith(
                          color: t.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (canBook)
                    Semantics(
                      button: true,
                      label: 'Book ${row.lane.name} now',
                      excludeSemantics: true,
                      child: Pressable(
                        onTap: onBook,
                        scale: 0.92,
                        minSize: 0,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: t.success,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              size: 20,
                              color: t.bg,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: t.textMuted,
                      ),
                    ),
                ],
              ),
              _DayBar(row: row, nowMin: nowMin),
            ],
          ),
        ),
      ),
    );
  }
}

(String, IconData) _presenceWords(LaneNow now) => switch (now.presence) {
  Presence.busy => (
    'With ${now.who ?? 'a customer'}',
    Icons.content_cut_rounded,
  ),
  Presence.onBreak => ('On a break', Icons.coffee_rounded),
  Presence.free => ('Free now', Icons.check_circle_rounded),
  Presence.later => ('Not in yet', Icons.schedule_rounded),
  Presence.done => ('Done for today', Icons.task_alt_rounded),
  Presence.off => (now.offReason ?? 'Away', Icons.bedtime_rounded),
};

String? _presenceWhen(LaneNow now) => switch (now.presence) {
  Presence.busy || Presence.onBreak =>
    now.freeAt == null ? null : 'Free at ${clockLabel(now.freeAt!)}',
  Presence.free => now.until == null ? null : 'until ${clockLabel(now.until!)}',
  Presence.later => now.until == null ? null : 'from ${clockLabel(now.until!)}',
  _ => null,
};

/// The barber's whole day on one thin line: working time in soft green, each
/// booking in its status colour, breaks grey, a red tick where "now" is, and the
/// first and last hour under it. Nothing to read, everything to see.
class _DayBar extends StatelessWidget {
  const _DayBar({required this.row, required this.nowMin});

  final _Row row;
  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final spans = <int>[
      for (final w in row.line.working) ...[w.$1, w.$2],
      for (final e in row.events) ...[e.startMin, e.endMin],
    ];
    if (spans.isEmpty) return const SizedBox.shrink();
    var start = spans.reduce((a, b) => a < b ? a : b);
    var end = spans.reduce((a, b) => a > b ? a : b);
    if (end - start < 60) end = start + 60;
    // Whole hours at both ends, so the two labels read cleanly.
    start = start ~/ 60 * 60;
    end = (end + 59) ~/ 60 * 60;

    final segments = <_Seg>[
      for (final w in row.line.working)
        _Seg(w.$1, w.$2, t.success.withValues(alpha: t.isDark ? 0.3 : 0.28)),
      for (final e in row.events)
        _Seg(
          e.startMin,
          e.endMin <= e.startMin ? e.startMin + 15 : e.endMin,
          e.isBreak
              ? t.textMuted.withValues(alpha: 0.55)
              : t
                    .statusColor(e.status)
                    .withValues(
                      alpha: (e.endMin <= nowMin && !e.isBreak) ? 0.5 : 1,
                    ),
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 4),
      child: Column(
        children: [
          SizedBox(
            height: 10,
            width: double.infinity,
            child: CustomPaint(
              painter: _DayBarPainter(
                start: start,
                end: end,
                segments: segments,
                nowMin: nowMin,
                track: t.border.withValues(alpha: 0.6),
                nowColor: t.danger,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                clockLabel(start),
                style: AppType.caption.copyWith(
                  color: t.textMuted,
                  fontSize: 10.5,
                ),
              ),
              Text(
                clockLabel(end),
                style: AppType.caption.copyWith(
                  color: t.textMuted,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Seg {
  const _Seg(this.start, this.end, this.color);

  final int start;
  final int end;
  final Color color;
}

class _DayBarPainter extends CustomPainter {
  _DayBarPainter({
    required this.start,
    required this.end,
    required this.segments,
    required this.nowMin,
    required this.track,
    required this.nowColor,
  });

  final int start;
  final int end;
  final List<_Seg> segments;
  final int nowMin;
  final Color track;
  final Color nowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (end - start).toDouble();
    double x(int m) => ((m - start) / span).clamp(0.0, 1.0) * size.width;

    final bar = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );
    canvas.save();
    canvas.clipRRect(bar);
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    for (final s in segments) {
      final a = x(s.start);
      final b = x(s.end);
      if (b - a < 1) continue;
      canvas.drawRect(
        Rect.fromLTRB(a, 0, b, size.height),
        Paint()..color = s.color,
      );
    }
    canvas.restore();

    if (nowMin >= start && nowMin <= end) {
      final nx = x(nowMin);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(nx - 1.25, -2, 2.5, size.height + 4),
          const Radius.circular(2),
        ),
        Paint()..color = nowColor,
      );
    }
  }

  @override
  bool shouldRepaint(_DayBarPainter old) =>
      old.start != start ||
      old.end != end ||
      old.nowMin != nowMin ||
      old.track != track ||
      old.nowColor != nowColor ||
      old.segments.length != segments.length ||
      !_sameSegs(old.segments, segments);

  static bool _sameSegs(List<_Seg> a, List<_Seg> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start ||
          a[i].end != b[i].end ||
          a[i].color != b[i].color) {
        return false;
      }
    }
    return true;
  }
}

/// A barber's day in a sheet: bookings, breaks and free time in order, with a
/// red line where now is. A booking opens its details, a free time starts a
/// booking at that time.
class _DayList extends StatelessWidget {
  const _DayList({
    required this.row,
    required this.nowMin,
    required this.onBooking,
    required this.onFree,
  });

  final _Row row;
  final int nowMin;
  final void Function(CalendarEvent event) onBooking;
  final void Function(CalendarLane lane, int minute) onFree;

  /// Bookings start on the quarter hour.
  static int _roundUp(int m) => (m + 14) ~/ 15 * 15;

  /// Cards in time order (free time that is already over is left out).
  List<_Item> _items() {
    return <_Item>[
      for (final e in row.events)
        _Item(
          e.isBreak ? _Kind.breakTime : _Kind.booking,
          e.startMin,
          e.endMin <= e.startMin ? e.startMin + 15 : e.endMin,
          event: e,
        ),
      for (final (s, e) in row.line.free)
        if (e > nowMin && e - (s < nowMin ? nowMin : s) >= 15)
          _Item(_Kind.free, s < nowMin ? nowMin : s, e),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  bool _live(_Item i) => nowMin >= i.start && nowMin < i.end;

  Widget _card(_Item i) {
    final live = _live(i);
    final over = i.end <= nowMin;
    return switch (i.kind) {
      _Kind.booking => _BookingCard(
        event: i.event!,
        live: live,
        over: over,
        width: double.infinity,
        onTap: () => onBooking(i.event!),
      ),
      _Kind.breakTime => _BreakCard(
        item: i,
        live: live,
        over: over,
        width: double.infinity,
      ),
      _Kind.free => _FreeCard(
        item: i,
        live: live,
        width: double.infinity,
        onTap: () => onFree(row.lane, _roundUp(i.start)),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final now = row.now;
    final (String words, IconData icon) = _presenceWords(now);
    final when = _presenceWhen(now);
    final items = _items();
    final anyLive = items.any(_live);
    final markerAt = anyLive ? -1 : items.indexWhere((i) => i.start > nowMin);

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i == markerAt) children.add(_NowLine(nowMin: nowMin));
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _card(items[i]),
        ),
      );
    }
    if (!anyLive && markerAt == -1 && items.isNotEmpty) {
      children.add(_NowLine(nowMin: nowMin));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: _presenceColor(t, now.presence)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                when == null ? words : '$words · $when',
                style: AppType.label.copyWith(color: t.text, fontSize: 13.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
            child: Text(
              'Nothing booked today.',
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: t.textSecondary),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

/// A red line across the list where "now" falls.
class _NowLine extends StatelessWidget {
  const _NowLine({required this.nowMin});

  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            'NOW ${clockLabel(nowMin)}',
            style: AppType.caption.copyWith(
              color: t.danger,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 2, color: t.danger)),
        ],
      ),
    );
  }
}

enum _Kind { booking, free, breakTime }

class _Item {
  const _Item(this.kind, this.start, this.end, {this.event});

  final _Kind kind;
  final int start;
  final int end;
  final CalendarEvent? event;
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.event,
    required this.live,
    required this.over,
    required this.onTap,
    this.width = _cardWidth,
  });

  final double width;
  final CalendarEvent event;
  final bool live;
  final bool over;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = t.statusColor(event.status);
    final end = event.endMin <= event.startMin
        ? event.startMin + 15
        : event.endMin;
    final word = _word(event.status);
    return Opacity(
      opacity: over ? 0.55 : 1,
      child: Semantics(
        button: true,
        label:
            '${event.title}, ${clockLabel(event.startMin)} to ${clockLabel(end)}, $word${live ? ', in progress' : ''}. Opens details.',
        excludeSemantics: true,
        child: Pressable(
          onTap: onTap,
          scale: 0.97,
          minSize: 0,
          child: Container(
            width: width,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                color.withValues(alpha: t.isDark ? 0.26 : 0.16),
                t.surface,
              ),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: live ? t.danger : color.withValues(alpha: 0.7),
                width: live ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(width: 4, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 4, 6, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Icon(event.status.icon, size: 12, color: color),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                live
                                    ? 'In progress'
                                    : _range(event.startMin, end),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.caption.copyWith(
                                  color: live ? t.danger : t.textSecondary,
                                  fontSize: 10.5,
                                  fontWeight: live
                                      ? FontWeight.w800
                                      : FontWeight.w500,
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
                            fontSize: 13.5,
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
      ),
    );
  }

  String _word(AppointmentStatus s) => switch (s) {
    AppointmentStatus.pending => 'Pending',
    AppointmentStatus.confirmed => 'Confirmed',
    AppointmentStatus.rescheduled => 'Rescheduled',
    AppointmentStatus.completed => 'Completed',
    AppointmentStatus.cancelled => 'Cancelled',
  };
}

class _BreakCard extends StatelessWidget {
  const _BreakCard({
    required this.item,
    required this.live,
    required this.over,
    this.width = _cardWidth * 0.85,
  });

  final double width;
  final _Item item;
  final bool live;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: over ? 0.55 : 1,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(9, 4, 6, 4),
        decoration: BoxDecoration(
          color: t.border.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: live ? t.warning : t.border,
            width: live ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(Icons.coffee_rounded, size: 12, color: t.textSecondary),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    _range(item.start, item.end),
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
            Text(
              'Break · ${spanLabel(item.end - item.start)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.bodyStrong.copyWith(color: t.text, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Free time: tap to book this barber right there.
class _FreeCard extends StatelessWidget {
  const _FreeCard({
    required this.item,
    required this.live,
    required this.onTap,
    this.width = _cardWidth,
  });

  final double width;
  final _Item item;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label:
          'Free ${live ? 'now ' : ''}until ${clockLabel(item.end)}, ${spanLabel(item.end - item.start)}. Opens a new booking.',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.97,
        minSize: 0,
        child: Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(9, 4, 6, 4),
          decoration: BoxDecoration(
            color: t.success.withValues(alpha: t.isDark ? 0.12 : 0.1),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: live ? t.success : t.success.withValues(alpha: 0.6),
              width: live ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      live
                          ? 'Free now'
                          : 'Free · ${spanLabel(item.end - item.start)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong.copyWith(
                        color: t.success,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      live
                          ? 'until ${clockLabel(item.end)}'
                          : _range(item.start, item.end),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: t.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: t.success,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_rounded, size: 17, color: t.bg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Barbers who are not working today: one quiet block, names under the reason.
class _AwayGroup extends StatelessWidget {
  const _AwayGroup({required this.rows});

  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reasons = <String>[];
    for (final r in rows) {
      final why = r.now.offReason ?? 'Away';
      if (!reasons.contains(why)) reasons.add(why);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: t.border.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.bedtime_rounded,
              size: 14,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final why in reasons)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$why: ',
                          style: AppType.label.copyWith(
                            color: t.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                        TextSpan(
                          text: [
                            for (final r in rows)
                              if ((r.now.offReason ?? 'Away') == why)
                                r.lane.name,
                          ].join(', '),
                          style: AppType.bodyStrong.copyWith(
                            color: t.text,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (reasons.contains('No hours set'))
                  Text(
                    'Without working hours they cannot be booked.',
                    style: AppType.caption.copyWith(
                      color: t.textMuted,
                      fontSize: 11,
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
