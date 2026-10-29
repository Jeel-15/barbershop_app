import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/domain/day_timeline.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/day_grid.dart';
import 'package:flutter/material.dart';

/// Home's "Staff Calendar" block: the shop floor right now, in plain words.
///
/// Three numbers (with a client / free / not in), the time and the shop hours,
/// then one card per barber who works today. A card says what the barber is
/// doing, then lists their day as a strip of cards in time order: bookings,
/// breaks and free time, with a red NOW marker between what is over and what is
/// next. Everything can be used right here: a booking opens its details and
/// actions, a free time starts a new booking at that time.
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

/// The barbers who work today, the first three open and the rest one tap away.
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
  static const _limit = 3;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = _all ? widget.rows : widget.rows.take(_limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in shown) ...[
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: t.border.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.border.withValues(alpha: 0.7)),
            ),
            child: _LaneCard(
              row: r,
              nowMin: widget.nowMin,
              onBooking: widget.onBooking,
              onFree: widget.onFree,
            ),
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: n == 0
              ? t.border.withValues(alpha: 0.3)
              : color.withValues(alpha: t.isDark ? 0.16 : 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: n == 0 ? t.border : color.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: n == 0 ? t.textMuted : color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$n',
              style: AppType.title.copyWith(
                color: n == 0 ? t.textMuted : t.text,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppType.caption.copyWith(
                color: t.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        chip(busy, 'with client', t.danger),
        chip(free, 'free now', t.success),
        chip(gone, 'not in', t.textMuted),
      ],
    );
  }
}

/// One barber: who they are and what they do now, then their day as cards.
class _LaneCard extends StatelessWidget {
  const _LaneCard({
    required this.row,
    required this.nowMin,
    required this.onBooking,
    required this.onFree,
  });

  final _Row row;
  final int nowMin;
  final void Function(CalendarEvent event) onBooking;
  final void Function(CalendarLane lane, int minute) onFree;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final now = row.now;
    final color = _presenceColor(t, now.presence);

    final (String words, IconData icon) = switch (now.presence) {
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
    final String? when = switch (now.presence) {
      Presence.busy || Presence.onBreak =>
        now.freeAt == null ? null : 'Free at ${clockLabel(now.freeAt!)}',
      Presence.free =>
        now.until == null ? null : 'until ${clockLabel(now.until!)}',
      Presence.later =>
        now.until == null ? null : 'from ${clockLabel(now.until!)}',
      _ => null,
    };
    final booked = row.bookings.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label:
              '${row.lane.name}. $words${when == null ? '' : ', $when'}. $booked booked.${now.noHours ? ' No working hours set for today.' : ''}',
          excludeSemantics: true,
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AppAvatar(
                    name: row.lane.name,
                    imageUrl: row.lane.photoUrl,
                    size: 34,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.surface, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),
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
                        fontSize: 14.5,
                      ),
                    ),
                    Row(
                      children: [
                        Icon(icon, size: 12, color: color),
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
                              fontSize: 12,
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
            ],
          ),
        ),
        const SizedBox(height: 10),
        _Strip(row: row, nowMin: nowMin, onBooking: onBooking, onFree: onFree),
      ],
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

/// The barber's day as cards in time order, a NOW marker where we are.
class _Strip extends StatefulWidget {
  const _Strip({
    required this.row,
    required this.nowMin,
    required this.onBooking,
    required this.onFree,
  });

  final _Row row;
  final int nowMin;
  final void Function(CalendarEvent event) onBooking;
  final void Function(CalendarLane lane, int minute) onFree;

  static const double cardWidth = 148;
  static const double gap = 8;
  static const double markerWidth = 56;

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  final _scroll = ScrollController();

  /// Cards in time order (free time that is already over is left out).
  List<_Item> _items() {
    final now = widget.nowMin;
    return <_Item>[
      for (final e in widget.row.events)
        _Item(
          e.isBreak ? _Kind.breakTime : _Kind.booking,
          e.startMin,
          e.endMin <= e.startMin ? e.startMin + 15 : e.endMin,
          event: e,
        ),
      for (final (s, e) in widget.row.line.free)
        if (e > now && e - (s < now ? now : s) >= 15)
          _Item(_Kind.free, s < now ? now : s, e),
    ]..sort((a, b) => a.start.compareTo(b.start));
  }

  bool _live(_Item i) => widget.nowMin >= i.start && widget.nowMin < i.end;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Bring "what is next" into view: the NOW card, or the first one not over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final items = _items();
      final firstOpen = items.indexWhere((i) => i.end > widget.nowMin);
      var offset = 0.0;
      if (firstOpen < 0) {
        offset = _scroll.position.maxScrollExtent;
      } else {
        for (var i = 0; i < firstOpen; i++) {
          offset += _widthOf(items[i]) + _Strip.gap;
        }
      }
      _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    final height = MediaQuery.textScalerOf(context).scale(34) + 18;
    final anyLive = items.any(_live);
    // Where the NOW marker goes: before the first card that has not started.
    final markerAt = anyLive
        ? -1
        : items.indexWhere((i) => i.start > widget.nowMin);

    final children = <Widget>[];
    void gap() => children.add(const SizedBox(width: _Strip.gap));
    for (var i = 0; i < items.length; i++) {
      if (i == markerAt) {
        children.add(_NowMarker(nowMin: widget.nowMin));
        gap();
      }
      children.add(_card(items[i]));
      gap();
    }
    if (!anyLive && markerAt == -1) {
      // Everything is over: the marker closes the day.
      children.add(_NowMarker(nowMin: widget.nowMin));
    }

    return SizedBox(
      height: height,
      child: ListView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        children: children,
      ),
    );
  }

  Widget _card(_Item i) {
    final lane = widget.row.lane;
    final live = _live(i);
    final over = i.end <= widget.nowMin;
    return switch (i.kind) {
      _Kind.booking => _BookingCard(
        event: i.event!,
        live: live,
        over: over,
        onTap: () => widget.onBooking(i.event!),
      ),
      _Kind.breakTime => _BreakCard(item: i, live: live, over: over),
      _Kind.free => _FreeCard(
        item: i,
        live: live,
        onTap: () => widget.onFree(lane, _roundUp(i.start)),
      ),
    };
  }

  double _widthOf(_Item i) =>
      i.kind == _Kind.breakTime ? _Strip.cardWidth * 0.85 : _Strip.cardWidth;

  /// Bookings start on the quarter hour.
  int _roundUp(int m) => (m + 14) ~/ 15 * 15;
}

class _NowMarker extends StatelessWidget {
  const _NowMarker({required this.nowMin});

  final int nowMin;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: _Strip.markerWidth,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: t.danger,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'NOW',
            style: AppType.caption.copyWith(
              color: t.danger,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            clockLabel(nowMin),
            maxLines: 1,
            style: AppType.caption.copyWith(
              color: t.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.event,
    required this.live,
    required this.over,
    required this.onTap,
  });

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
            width: _Strip.cardWidth,
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
  });

  final _Item item;
  final bool live;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Opacity(
      opacity: over ? 0.55 : 1,
      child: Container(
        width: _Strip.cardWidth * 0.85,
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
  });

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
          width: _Strip.cardWidth,
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
