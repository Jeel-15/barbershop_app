import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';

/// Why a spot of a barber's column can or cannot take a booking. The same
/// rules as the web's staff calendar: only free working time is clickable.
enum SlotVerdict {
  /// Working time with nothing booked: a booking can start here.
  free,

  /// Under an appointment.
  booked,

  /// Under a break.
  onBreak,

  /// Outside the barber's working hours (or no hours set at all).
  unavailable,

  /// The barber has the whole day off.
  dayOff,

  /// The shop is closed this day.
  shopClosed,
}

/// Why a whole column looks the way it does.
enum LaneState {
  open,
  dayOff,

  /// The barber has no working hours for this weekday.
  noHours,
  shopClosed,
}

/// One barber's day: where they work, where they are busy, where a booking
/// fits. Pure data, no widgets, so the rules can be tested alone.
class LaneTimeline {
  LaneTimeline._({
    required this.state,
    required this.working,
    required this.busy,
  });

  /// Builds the timeline of [laneId] on [day]. Like the web, the clock plays no
  /// part: free time earlier today can still be booked (back entry).
  factory LaneTimeline.of(CalendarDay day, int laneId) {
    final a = day.availability;
    final staff = a.staff[laneId];

    var state = LaneState.open;
    List<(int, int)> working;
    if (a.shopDayOff) {
      state = LaneState.shopClosed;
      working = const [];
    } else if (staff == null) {
      // No data for this barber (or the server was not asked): like the web,
      // nothing is blocked; the shop hours apply.
      working = [(a.openMin, a.closeMin)];
    } else if (staff.isDayOff) {
      state = LaneState.dayOff;
      working = const [];
    } else if (staff.hours.isEmpty) {
      state = LaneState.noHours;
      working = const [];
    } else {
      working = _merge(staff.hours);
    }

    final busy = <(int, int)>[
      for (final e in day.forLane(laneId)) (e.startMin, _end(e)),
      ...?staff?.breaks,
    ];
    return LaneTimeline._(state: state, working: working, busy: _merge(busy));
  }

  final LaneState state;

  /// Working blocks, merged and sorted (minutes since midnight).
  final List<(int, int)> working;

  /// Appointments and breaks, merged and sorted.
  final List<(int, int)> busy;

  /// A booking never shows shorter than a quarter of an hour.
  static int _end(CalendarEvent e) =>
      e.endMin <= e.startMin ? e.startMin + 15 : e.endMin;

  static List<(int, int)> _merge(List<(int, int)> raw) {
    final list = [
      for (final r in raw)
        if (r.$2 > r.$1) r,
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    final out = <(int, int)>[];
    for (final r in list) {
      if (out.isNotEmpty && r.$1 <= out.last.$2) {
        if (r.$2 > out.last.$2) out[out.length - 1] = (out.last.$1, r.$2);
      } else {
        out.add(r);
      }
    }
    return out;
  }

  bool get isOpen => state == LaneState.open;

  /// Working time minus busy time: the green "free" stretches.
  List<(int, int)> get free {
    final out = <(int, int)>[];
    for (final (ws, we) in working) {
      var cursor = ws;
      for (final (bs, be) in busy) {
        if (be <= cursor || bs >= we) continue;
        if (bs > cursor) out.add((cursor, bs));
        if (be > cursor) cursor = be;
      }
      if (cursor < we) out.add((cursor, we));
    }
    return out;
  }

  /// Hours the grid should cover for this barber (min start, max end), or null.
  (int, int)? get span {
    if (working.isEmpty) return null;
    return (working.first.$1, working.last.$2);
  }

  /// What a tap at [minute] means.
  SlotVerdict verdict(int minute) {
    switch (state) {
      case LaneState.shopClosed:
        return SlotVerdict.shopClosed;
      case LaneState.dayOff:
        return SlotVerdict.dayOff;
      case LaneState.noHours:
        return SlotVerdict.unavailable;
      case LaneState.open:
        break;
    }
    if (!_inside(working, minute)) return SlotVerdict.unavailable;
    for (final e in busy) {
      if (minute >= e.$1 && minute < e.$2) return SlotVerdict.booked;
    }
    return SlotVerdict.free;
  }

  /// End of the free stretch that holds [minute] (null when it is not free).
  int? freeUntil(int minute) {
    for (final (s, e) in free) {
      if (minute >= s && minute < e) return e;
    }
    return null;
  }

  static bool _inside(List<(int, int)> blocks, int m) {
    for (final b in blocks) {
      if (m >= b.$1 && m < b.$2) return true;
    }
    return false;
  }

  /// The stretches inside [from, to] where the barber does not work (hatched).
  List<(int, int)> unavailable(int from, int to) {
    final out = <(int, int)>[];
    var cursor = from;
    for (final (s, e) in working) {
      if (s > cursor) out.add((cursor, s < to ? s : to));
      if (e > cursor) cursor = e < to ? e : to;
    }
    if (cursor < to) out.add((cursor, to));
    return [
      for (final r in out)
        if (r.$2 > r.$1) r,
    ];
  }
}

/// How many bookings of each status a day has (the legend's numbers).
class DayCounts {
  const DayCounts(this.byStatus, this.breaks);

  factory DayCounts.of(CalendarDay day) {
    final m = <int, int>{};
    var breaks = 0;
    // Only what has a column on screen (a non-barber's booking has none).
    final shown = {for (final l in day.lanes) l.id};
    for (final e in day.events) {
      if (!shown.contains(e.laneId)) continue;
      if (e.isBreak) {
        breaks++;
      } else {
        m[e.status.code] = (m[e.status.code] ?? 0) + 1;
      }
    }
    return DayCounts(m, breaks);
  }

  final Map<int, int> byStatus;
  final int breaks;

  int of(int statusCode) => byStatus[statusCode] ?? 0;

  int get bookings => byStatus.values.fold(0, (a, b) => a + b);
}

/// What one barber is doing at this minute, the way an owner reads it.
enum Presence {
  /// With a customer.
  busy,

  /// On a break.
  onBreak,

  /// Working and nobody is booked now.
  free,

  /// Not at the chair yet; starts later today.
  later,

  /// Worked today and has nothing left.
  done,

  /// Not working today (day off, no hours set, shop closed).
  off,
}

/// A barber's state at [nowMin], with the times a sentence needs.
class LaneNow {
  const LaneNow({
    required this.presence,
    this.who,
    this.until,
    this.freeAt,
    this.noHours = false,
    this.offReason,
  });

  /// [bookings] are the barber's appointments of the day (no breaks).
  factory LaneNow.of(
    LaneTimeline line,
    List<CalendarEvent> bookings,
    int nowMin,
  ) {
    final sorted = [...bookings]
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    CalendarEvent? current;
    for (final b in sorted) {
      if (nowMin >= b.startMin && nowMin < LaneTimeline._end(b)) current = b;
    }

    // No hours set but booked anyway: judge by the bookings alone.
    if (line.state == LaneState.noHours && sorted.isNotEmpty) {
      if (current != null) {
        return LaneNow(
          presence: Presence.busy,
          who: current.title,
          freeAt: LaneTimeline._end(current),
          noHours: true,
        );
      }
      final next = sorted.where((b) => b.startMin > nowMin).toList();
      return next.isEmpty
          ? const LaneNow(presence: Presence.done, noHours: true)
          : LaneNow(
              presence: Presence.later,
              until: next.first.startMin,
              noHours: true,
            );
    }

    if (!line.isOpen) {
      return LaneNow(
        presence: Presence.off,
        offReason: switch (line.state) {
          LaneState.dayOff => 'Day off',
          LaneState.noHours => 'No hours set',
          _ => 'Shop closed',
        },
      );
    }

    for (final (s, e) in line.busy) {
      if (nowMin >= s && nowMin < e) {
        final working = line.working.any((w) => e < w.$2);
        return LaneNow(
          presence: current == null ? Presence.onBreak : Presence.busy,
          who: current?.title,
          freeAt: working ? e : null,
        );
      }
    }
    for (final (s, e) in line.free) {
      if (nowMin >= s && nowMin < e) {
        return LaneNow(presence: Presence.free, until: e);
      }
    }
    for (final (s, _) in line.working) {
      if (s > nowMin) return LaneNow(presence: Presence.later, until: s);
    }
    return const LaneNow(presence: Presence.done);
  }

  final Presence presence;

  /// The customer being served (busy).
  final String? who;

  /// free: the free stretch ends; later: the shift starts.
  final int? until;

  /// busy / on a break: when the barber is free again (null = not today).
  final int? freeAt;

  /// Booked although the barber has no working hours for the day.
  final bool noHours;

  /// Why a barber who is [Presence.off] is off.
  final String? offReason;

  /// Counts toward "Free" on the board: can take a walk-in right now.
  bool get canTakeWalkIn => presence == Presence.free;
}
