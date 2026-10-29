import 'package:barbershop_app/design_system/tokens/colors.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';

/// One barber column.
class CalendarLane {
  const CalendarLane({required this.id, required this.name, this.photoUrl});

  factory CalendarLane.fromJson(Map<String, dynamic> j) => CalendarLane(
    id: (j['id'] as num).toInt(),
    name: (j['name'] ?? 'Staff').toString(),
    photoUrl: j['profile_image_url']?.toString(),
  );

  final int id;
  final String name;
  final String? photoUrl;
}

/// An appointment or a break on one barber's lane (`GET /calendar/events`).
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.isBreak,
    required this.laneId,
    required this.title,
    required this.date,
    required this.startMin,
    required this.endMin,
    required this.staffName,
    this.appointmentId,
    this.status = AppointmentStatus.pending,
    this.phone,
    this.email,
    this.notes,
    this.serviceNames = '',
    this.isFirstAvailable = false,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> j) {
    // "2026-10-26 09:30:00"
    final start = (j['start'] ?? '').toString();
    final end = (j['end'] ?? '').toString();
    int mins(String s) {
      final t = s.length >= 16 ? s.substring(11, 16) : '00:00';
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final isBreak = j['type'] == 'break';
    return CalendarEvent(
      id: (j['id'] ?? '').toString(),
      isBreak: isBreak,
      laneId: int.tryParse((j['resource_id'] ?? '').toString()) ?? 0,
      title: (j['title'] ?? (isBreak ? 'Break' : 'Booking')).toString(),
      date: start.length >= 10 ? start.substring(0, 10) : '',
      startMin: mins(start),
      endMin: mins(end),
      staffName: (j['staff_name'] ?? '').toString(),
      appointmentId: (j['appointment_id'] as num?)?.toInt(),
      status: AppointmentStatus.fromCode((j['status'] as num?)?.toInt() ?? 0),
      phone: j['phone']?.toString(),
      email: j['email']?.toString(),
      notes: j['notes']?.toString(),
      serviceNames: (j['service_names'] ?? '').toString(),
      isFirstAvailable: j['is_first_available_lane'] == true,
    );
  }

  final String id;
  final bool isBreak;
  final int laneId;

  /// Customer name (or "Break").
  final String title;

  /// `yyyy-MM-dd`.
  final String date;

  /// Minutes since midnight, shop time.
  final int startMin;
  final int endMin;
  final String staffName;
  final int? appointmentId;
  final AppointmentStatus status;
  final String? phone;
  final String? email;
  final String? notes;

  /// "Men's cut ×1, Beard ×1".
  final String serviceNames;
  final bool isFirstAvailable;

  int get duration => endMin - startMin;

  /// The same booking as an appointment-list row (what the shutter opens).
  AppointmentRow toAppointmentRow(List<String> actions) {
    String hhmm(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    String label(int m) {
      final h = m ~/ 60 % 24;
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '${h12.toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
    }

    return AppointmentRow(
      id: appointmentId ?? 0,
      date: date,
      start: hhmm(startMin),
      end: hhmm(endMin),
      startLabel: label(startMin),
      endLabel: label(endMin),
      status: status,
      customerName: title,
      customerPhone: phone,
      staffNames: [if (staffName.isNotEmpty) staffName],
      lines: const [],
      actions: actions,
    );
  }
}

/// Opening hours and per-barber hours of one day (`GET /calendar/availability`).
class DayAvailability {
  const DayAvailability({
    required this.openMin,
    required this.closeMin,
    required this.shopDayOff,
    required this.staff,
    this.known = true,
  });

  factory DayAvailability.fromJson(Map<String, dynamic> j) {
    int mins(Object? v, int fallback) {
      final s = v?.toString() ?? '';
      if (!s.contains(':')) return fallback;
      final p = s.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final raw = Map<String, dynamic>.from((j['staff'] as Map?) ?? const {});
    return DayAvailability(
      openMin: mins(j['shop_open'], 9 * 60),
      closeMin: mins(j['shop_close'], 21 * 60),
      shopDayOff: j['shop_day_off'] == true,
      staff: {
        for (final e in raw.entries)
          int.parse(e.key): StaffDay.fromJson(
            Map<String, dynamic>.from(e.value as Map),
            mins,
          ),
      },
    );
  }

  /// The server could not be asked (or has not answered yet): nothing is
  /// blocked, the shop is assumed open 9-21. Never used to say "closed".
  factory DayAvailability.fallback() => const DayAvailability(
    openMin: 9 * 60,
    closeMin: 21 * 60,
    shopDayOff: false,
    staff: {},
    known: false,
  );

  final int openMin;
  final int closeMin;
  final bool shopDayOff;
  final Map<int, StaffDay> staff;

  /// False for [DayAvailability.fallback].
  final bool known;
}

class StaffDay {
  const StaffDay({
    required this.isDayOff,
    required this.hours,
    this.breaks = const [],
  });

  factory StaffDay.fromJson(
    Map<String, dynamic> j,
    int Function(Object?, int) mins,
  ) => StaffDay(
    isDayOff: j['is_day_off'] == true,
    hours: [
      for (final h in (j['working_hours'] as List? ?? const []))
        (mins(h['start'], 0), mins(h['end'], 24 * 60)),
    ],
    breaks: [
      for (final b in (j['breaks'] as List? ?? const []))
        (mins(b['start'], 0), mins(b['end'], 24 * 60)),
    ],
  );

  final bool isDayOff;

  /// Working blocks (start, end) in minutes. Empty = no working hours set:
  /// the web shows the whole column as "Not Available".
  final List<(int, int)> hours;

  /// Breaks added for this day (start, end) in minutes.
  final List<(int, int)> breaks;
}

/// Everything the Calendar draws for one day.
class CalendarDay {
  const CalendarDay({
    required this.lanes,
    required this.events,
    required this.availability,
  });

  final List<CalendarLane> lanes;
  final List<CalendarEvent> events;
  final DayAvailability availability;

  List<CalendarEvent> forLane(int laneId) => [
    for (final e in events)
      if (e.laneId == laneId) e,
  ];

  int get bookingCount => events.where((e) => !e.isBreak).length;
}
