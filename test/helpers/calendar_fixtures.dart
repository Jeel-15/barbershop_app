import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';

Map<String, dynamic> _appt(
  int id,
  int staff,
  String staffName,
  String date,
  String start,
  String end,
  int status,
  String customer,
  String services, {
  String phone = '7805550101',
}) => {
  'id': 'appt_${id}_staff_$staff',
  'type': 'appointment',
  'resource_id': '$staff',
  'title': customer,
  'start': '$date $start:00',
  'end': '$date $end:00',
  'appointment_id': id,
  'status': status,
  'status_key': 'x',
  'status_label': 'x',
  'staff_id': staff,
  'staff_name': staffName,
  'is_first_available_lane': false,
  'phone': phone,
  'email': null,
  'notes': null,
  'service_ids': [1],
  'service_names': services,
  'duration': 30,
};

/// Raw `GET /calendar/events` shaped like the real API.
Map<String, dynamic> calendarRaw(String day) => {
  'lanes': [
    {'id': 42, 'name': 'Mike', 'profile_image_url': null},
    {'id': 49, 'name': 'Mutaz', 'profile_image_url': null},
  ],
  'events': [
    _appt(
      1,
      42,
      'Mike',
      day,
      '10:00',
      '10:30',
      3,
      'Marcus Lee',
      "Men's cut ×1",
    ),
    _appt(
      2,
      42,
      'Mike',
      day,
      '11:00',
      '11:45',
      0,
      'Daniel Okafor',
      "Men's cut ×1, Beard ×1",
    ),
    _appt(
      3,
      49,
      'Mutaz',
      day,
      '13:30',
      '14:00',
      4,
      'Sam Patel',
      'Skin fade ×1',
    ),
    // Staff who is not a barber has no column, exactly like the web.
    _appt(
      4,
      47,
      'JOJO',
      day,
      '16:00',
      '16:30',
      0,
      'Ahmed Khan',
      "Men's cut ×1",
    ),
    {
      'id': 'break_9',
      'type': 'break',
      'resource_id': '49',
      'title': 'Break',
      'start': '$day 12:00:00',
      'end': '$day 12:45:00',
      'staff_id': 49,
      'staff_name': 'Mutaz',
      'break_id': 9,
    },
  ],
};

CalendarWindow calendarWindow(String day) {
  final raw = calendarRaw(day);
  return CalendarWindow(
    from: DateTime.parse(day).subtract(const Duration(days: 7)),
    to: DateTime.parse(day).add(const Duration(days: 45)),
    lanes: [
      for (final l in raw['lanes'] as List)
        CalendarLane.fromJson(Map<String, dynamic>.from(l as Map)),
    ],
    events: [
      for (final e in raw['events'] as List)
        CalendarEvent.fromJson(Map<String, dynamic>.from(e as Map)),
    ],
  );
}

/// Calendar controller with fixed data (no network).
class FixedCalendar extends CalendarController {
  FixedCalendar(this.window);

  final CalendarWindow window;
  int refreshes = 0;

  @override
  Future<CalendarWindow> build() async => window;

  @override
  Future<void> refresh() async {
    refreshes++;
  }

  @override
  Future<void> ensure(DateTime day) async {}
}
