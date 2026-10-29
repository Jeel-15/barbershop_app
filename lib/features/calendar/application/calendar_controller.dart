import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/data/calendar_repository.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which day the Calendar tab shows.
class CalendarDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => ShopTime.today();

  void select(DateTime day) => state = ShopTime.dateOnly(day);
}

final calendarDateProvider = NotifierProvider<CalendarDateNotifier, DateTime>(
  CalendarDateNotifier.new,
);

/// "Filter by Staff" (web, admin): null = All Staff, otherwise one barber's column.
class CalendarStaffFilter extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? staffId) => state = staffId;
}

final calendarStaffFilterProvider = NotifierProvider<CalendarStaffFilter, int?>(
  CalendarStaffFilter.new,
);

/// The order of the barber columns (web: drag a column header). Ids not in
/// the list keep their natural place after the ordered ones.
class CalendarOrder extends Notifier<List<int>> {
  @override
  List<int> build() {
    try {
      return ref.read(appPrefsProvider).calendarOrder;
    } catch (_) {
      return const [];
    }
  }

  Future<void> set(List<int> ids) async {
    state = ids;
    try {
      await ref.read(appPrefsProvider).setCalendarOrder(ids);
    } catch (_) {
      // Kept for this session only.
    }
  }
}

final calendarOrderProvider = NotifierProvider<CalendarOrder, List<int>>(
  CalendarOrder.new,
);

/// Pinch to zoom: how many pixels one hour takes in the day grid.
const double kHourMin = 64;
const double kHourMax = 176;
const double kHourDefault = 88;

/// The steps of the zoom button: Compact, Normal, Roomy.
const List<double> kHourSteps = [64, kHourDefault, 132];

class CalendarZoom extends Notifier<double> {
  @override
  double build() {
    try {
      final v = ref.read(appPrefsProvider).calendarHourHeight;
      return (v ?? kHourDefault).clamp(kHourMin, kHourMax);
    } catch (_) {
      return kHourDefault;
    }
  }

  Future<void> set(double px) async {
    state = px.clamp(kHourMin, kHourMax);
    try {
      await ref.read(appPrefsProvider).setCalendarHourHeight(state);
    } catch (_) {
      // Kept for this session only.
    }
  }

  /// The button: the next step up from here (Roomy wraps to Compact).
  Future<void> step() {
    final next = kHourSteps.firstWhere(
      (s) => s > state + 4,
      orElse: () => kHourSteps.first,
    );
    return set(next);
  }
}

final calendarZoomProvider = NotifierProvider<CalendarZoom, double>(
  CalendarZoom.new,
);

/// Landscape calendar: pixels per hour (time runs sideways there). null = one of
/// the two presets (whole day / more detail), which the top bar button toggles.
const double kPphMin = 48;
const double kPphMax = 360;

class LandscapeZoom extends Notifier<double?> {
  @override
  double? build() {
    try {
      final v = ref.read(appPrefsProvider).landscapeHourWidth;
      return v?.clamp(kPphMin, kPphMax);
    } catch (_) {
      return null;
    }
  }

  Future<void> set(double? px) async {
    state = px?.clamp(kPphMin, kPphMax);
    try {
      await ref.read(appPrefsProvider).setLandscapeHourWidth(state);
    } catch (_) {}
  }
}

final landscapeZoomProvider = NotifierProvider<LandscapeZoom, double?>(
  LandscapeZoom.new,
);

/// Whether the one-time "pinch with two fingers" tip is still to be shown.
class CalendarZoomHint extends Notifier<bool> {
  @override
  bool build() {
    try {
      return !ref.read(appPrefsProvider).calendarZoomHintSeen;
    } catch (_) {
      return false;
    }
  }

  Future<void> dismiss() async {
    state = false;
    try {
      await ref.read(appPrefsProvider).setCalendarZoomHintSeen();
    } catch (_) {}
  }
}

final calendarZoomHintProvider = NotifierProvider<CalendarZoomHint, bool>(
  CalendarZoomHint.new,
);

/// [lanes] in the user's [order]; any lane not named in it follows, in the
/// server's order.
List<CalendarLane> orderLanes(List<CalendarLane> lanes, List<int> order) {
  if (order.isEmpty) return lanes;
  final byId = {for (final l in lanes) l.id: l};
  return [for (final id in order) ?byId.remove(id), ...byId.values];
}

/// A run of days fetched in one call: switching days inside it is instant and
/// the date strip can show a dot on every busy day.
class CalendarWindow {
  const CalendarWindow({
    required this.from,
    required this.to,
    required this.lanes,
    required this.events,
  });

  final DateTime from;
  final DateTime to;
  final List<CalendarLane> lanes;
  final List<CalendarEvent> events;

  bool covers(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

  List<CalendarEvent> eventsOn(DateTime d) {
    final key = ShopTime.ymd(d);
    return [
      for (final e in events)
        if (e.date == key) e,
    ];
  }

  CalendarDay day(
    DateTime d,
    DayAvailability availability, {
    int? onlyStaffId,
    List<int> order = const [],
  }) {
    final ev = [
      for (final e in eventsOn(d))
        if (onlyStaffId == null || e.laneId == onlyStaffId) e,
    ];
    return CalendarDay(
      // Same columns as the web: only barbers. A booking on a staff member
      // who is not marked as a barber has no column there either.
      lanes: orderLanes(
        onlyStaffId == null
            ? lanes
            : [
                for (final l in lanes)
                  if (l.id == onlyStaffId) l,
              ],
        order,
      ),
      events: ev,
      availability: availability,
    );
  }

  Set<DateTime> get busyDays => {
    for (final e in events)
      if (!e.isBreak) ShopTime.parseDate(e.date),
  };
}

final calendarProvider =
    AsyncNotifierProvider<CalendarController, CalendarWindow>(
      CalendarController.new,
      retry: (_, _) => null,
    );

class CalendarController extends AsyncNotifier<CalendarWindow> {
  @override
  Future<CalendarWindow> build() async {
    // Staff and admin get different lanes from the server; reload on user change.
    ref.watch(currentUserProvider);
    return _load(ShopTime.today());
  }

  Future<CalendarWindow> _load(DateTime center) async {
    final from = center.subtract(const Duration(days: 7));
    final to = center.add(const Duration(days: 45));
    final res = await ref
        .read(calendarRepositoryProvider)
        .events(ShopTime.ymd(from), ShopTime.ymd(to));
    return CalendarWindow(
      from: from,
      to: to,
      lanes: res.lanes,
      events: res.events,
    );
  }

  /// Makes sure [day] is inside the fetched window (the strip can scroll far).
  Future<void> ensure(DateTime day) async {
    final w = state.value;
    if (w == null || w.covers(day)) return;
    state = AsyncData(await _load(day));
  }

  /// Pull-to-refresh and after any change: re-fetch around the shown day.
  Future<void> refresh() async {
    final center = ref.read(calendarDateProvider);
    // Working hours and breaks may have changed since the day was drawn.
    ref.invalidate(dayAvailabilityProvider);
    final fresh = await _load(center);
    state = AsyncData(fresh);
  }
}

/// Shop opening hours and barber hours for one day. Falls back to 9-21 if the
/// call fails, so the grid still draws.
final dayAvailabilityProvider = FutureProvider.autoDispose
    .family<DayAvailability, String>((ref, date) async {
      try {
        return await ref.read(calendarRepositoryProvider).availability(date);
      } catch (_) {
        return DayAvailability.fallback();
      }
    });
