import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../config/env.dart';

/// "Now", "today" and date text in the SHOP's time zone (America/Edmonton),
/// whatever the phone's own zone is (decision D14). The API sends plain
/// shop-local dates (`2026-10-23`) and times (`14:30`), so no conversion of
/// stored values is ever needed; only "what is today" must come from here.
class ShopTime {
  static bool _ready = false;
  static late tz.Location _loc;

  /// Replaceable in tests.
  static DateTime Function() clock = DateTime.now;

  static void init() {
    if (_ready) return;
    tzdata.initializeTimeZones();
    _loc = tz.getLocation(Env.shopTimeZone);
    _ready = true;
  }

  static tz.TZDateTime now() {
    init();
    return tz.TZDateTime.from(clock().toUtc(), _loc);
  }

  /// Today as a date-only value (midnight), comparable with other date-only values.
  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isToday(DateTime d) => isSameDay(d, today());

  /// `2026-10-23`, as the API wants it.
  static String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Parses the API's `2026-10-23` (a time part, if present, is ignored).
  static DateTime parseDate(String s) {
    final p = s.substring(0, 10).split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  /// `14:30` or `14:30:00` -> minutes since midnight (870).
  static int minutes(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  /// 870 -> `14:30` (API format).
  static String hhmm(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  /// `14:30` or 870 -> `2:30 PM`.
  static String timeLabel(Object time) {
    final m = time is int ? time : minutes(time as String);
    final h24 = (m ~/ 60) % 24;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h:${(m % 60).toString().padLeft(2, '0')} ${h24 < 12 ? 'AM' : 'PM'}';
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekdaysLong = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String weekdayShort(DateTime d) => _weekdays[d.weekday - 1];
  static String weekdayLong(DateTime d) => _weekdaysLong[d.weekday - 1];

  /// `Thu, 23 Oct`.
  static String dayLabel(DateTime d) =>
      '${weekdayShort(d)}, ${d.day} ${_months[d.month - 1]}';

  /// `Today`, `Tomorrow`, `Yesterday` or `Thu, 23 Oct`.
  static String relativeDay(DateTime d) {
    final diff = dateOnly(d).difference(today()).inDays;
    return switch (diff) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => dayLabel(d),
    };
  }

  /// `23 Oct 2026`.
  static String fullDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';
}
