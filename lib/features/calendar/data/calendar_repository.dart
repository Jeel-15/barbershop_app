import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// CAL-1..3: events and lanes, one day's hours, and ad-hoc breaks.
class CalendarRepository {
  const CalendarRepository(this._api);

  final ApiClient _api;

  /// Lanes (barbers) and every appointment/break between [from] and [to]
  /// (`yyyy-MM-dd`, inclusive). [staffId] narrows to one barber.
  Future<({List<CalendarLane> lanes, List<CalendarEvent> events})> events(
    String from,
    String to, {
    int? staffId,
  }) async {
    final res = await _api.get(
      '/calendar/events',
      query: {'from': from, 'to': to, 'staff_id': ?staffId},
    );
    return (
      lanes: [
        for (final l in (res.data['lanes'] as List? ?? const []))
          CalendarLane.fromJson(Map<String, dynamic>.from(l as Map)),
      ],
      events: [
        for (final e in (res.data['events'] as List? ?? const []))
          CalendarEvent.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }

  Future<DayAvailability> availability(String date) async {
    final res = await _api.get('/calendar/availability', query: {'date': date});
    return DayAvailability.fromJson(res.data);
  }

  /// A break that starts now and lasts [hours]:[minutes], or the rest of the
  /// day (web "Add Breaks").
  Future<void> addBreak({
    required int staffId,
    bool restOfDay = false,
    int hours = 0,
    int minutes = 0,
  }) async {
    await _api.post(
      '/calendar/breaks',
      body: {
        'staff_id': staffId,
        'rest_of_day': restOfDay,
        if (!restOfDay) 'hour': hours,
        if (!restOfDay) 'minute': minutes,
      },
    );
  }
}

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => CalendarRepository(ref.watch(apiClientProvider)),
);
