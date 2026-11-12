import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/home/presentation/widgets/home_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/load_fonts.dart';

CalendarEvent _a(int lane, String who, int s, int e, int status) =>
    CalendarEvent(
      id: '$lane-$s',
      isBreak: false,
      laneId: lane,
      title: who,
      date: '2026-10-27',
      startMin: s,
      endMin: e,
      staffName: '',
      appointmentId: s,
      status: AppointmentStatus.fromCode(status),
    );

const _lanes = [
  CalendarLane(id: 1, name: 'Mike'),
  CalendarLane(id: 2, name: 'Mutaz'),
  CalendarLane(id: 3, name: 'Rossie'),
  CalendarLane(id: 4, name: 'Daniel'),
];

CalendarDay _day(List<CalendarEvent> events) => CalendarDay(
  lanes: _lanes,
  events: events,
  availability: const DayAvailability(
    openMin: 9 * 60,
    closeMin: 20 * 60,
    shopDayOff: false,
    staff: {
      1: StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
      2: StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
      3: StaffDay(isDayOff: true, hours: []),
      4: StaffDay(isDayOff: false, hours: []),
    },
  ),
);

class _Taps {
  final bookings = <CalendarEvent>[];
  final frees = <(CalendarLane, int)>[];
}

/// A sheet rises and falls; give it time.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Taps> _pump(WidgetTester tester, CalendarDay day) async {
  final taps = _Taps();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: StaffCalendarCard(
            day: day,
            onBooking: taps.bookings.add,
            onFree: (lane, minute) => taps.frees.add((lane, minute)),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return taps;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
  });

  testWidgets('shows the time, counts the floor, says what each barber does', (
    tester,
  ) async {
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 16, 10); // 10:10
    await _pump(
      tester,
      _day([
        _a(1, 'Marcus Lee', 9 * 60 + 30, 10 * 60 + 15, 3),
        _a(1, 'Sam', 15 * 60, 15 * 60 + 30, 0),
      ]),
    );
    expect(find.text('NOW 10:10 AM'), findsOneWidget);
    expect(find.text('Open until 8:00 PM'), findsOneWidget);
    // Mike busy; Mutaz free; Rossie off; Daniel no hours.
    expect(find.text('with client'), findsOneWidget);
    expect(find.text('not in'), findsOneWidget);
    expect(find.text('With Marcus Lee'), findsOneWidget);
    expect(find.text('Free at 10:15 AM'), findsOneWidget);
    expect(find.text('2 bookings'), findsOneWidget);
  });

  testWidgets('a barber row opens the day, and a booking opens that booking', (
    tester,
  ) async {
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 16, 10);
    final taps = await _pump(
      tester,
      _day([_a(1, 'Marcus Lee', 9 * 60 + 30, 10 * 60 + 15, 3)]),
    );
    // The booking is not on the page itself, only in the barber's day.
    expect(find.text('Marcus Lee'), findsNothing);
    await tester.tap(find.text('Mike'));
    await _settle(tester);
    expect(find.text('In progress'), findsOneWidget);
    await tester.tap(find.text('Marcus Lee'));
    await _settle(tester);
    expect(taps.bookings.single.title, 'Marcus Lee');
    // The sheet closed before the booking opened.
    expect(find.text('In progress'), findsNothing);
  });

  testWidgets('the plus on a free barber books them right now', (tester) async {
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 16, 10);
    final taps = await _pump(
      tester,
      _day([_a(1, 'Marcus Lee', 9 * 60 + 30, 10 * 60 + 15, 3)]),
    );
    // Mutaz is free now (10:10 until 18:00): the first "+" is his.
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    final (lane, minute) = taps.frees.single;
    expect(lane.name, isNotEmpty);
    expect(minute % 15, 0, reason: 'bookings start on the quarter hour');
    expect(minute, 10 * 60 + 15);
  });

  testWidgets('a free time in the barber day starts a booking there', (
    tester,
  ) async {
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 16, 10);
    final taps = await _pump(tester, _day(const []));
    await tester.tap(find.text('Mutaz'));
    await _settle(tester);
    expect(find.text('Free now'), findsWidgets);
    // Both the row and the day list have a plus; the list is on top.
    await tester.tap(find.byIcon(Icons.add_rounded).last);
    await _settle(tester);
    expect(taps.frees.single.$1.name, 'Mutaz');
  });

  testWidgets('each barber has a day bar with the first and last hour', (
    tester,
  ) async {
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 16, 10);
    await _pump(tester, _day(const []));
    expect(find.text('9:00 AM'), findsWidgets);
    expect(find.text('6:00 PM'), findsWidgets);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('more than four barbers: the rest are one tap away', (
    tester,
  ) async {
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 16, 10);
    final lanes = [
      for (var i = 1; i <= 6; i++) CalendarLane(id: i, name: 'B$i'),
    ];
    final day = CalendarDay(
      lanes: lanes,
      events: const [],
      availability: DayAvailability(
        openMin: 9 * 60,
        closeMin: 20 * 60,
        shopDayOff: false,
        staff: {
          for (var i = 1; i <= 6; i++)
            i: const StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
        },
      ),
    );
    await _pump(tester, day);
    expect(find.text('B5'), findsNothing);
    await tester.tap(find.text('Show 2 more barbers'));
    await tester.pump();
    expect(find.text('B5'), findsOneWidget);
    expect(find.text('Show fewer barbers'), findsOneWidget);
  });

  testWidgets('before opening the NOW marker and shop hours explain it', (
    tester,
  ) async {
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 8, 24); // 02:24
    await _pump(tester, _day(const []));
    expect(find.text('Opens at 9:00 AM'), findsOneWidget);
    expect(find.text('Not in yet'), findsWidgets);
  });

  testWidgets('barbers who do not work are grouped under their reason', (
    tester,
  ) async {
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 20, 6);
    await _pump(tester, _day(const []));
    expect(find.textContaining('Day off: Rossie'), findsOneWidget);
    expect(find.textContaining('No hours set: Daniel'), findsOneWidget);
    expect(find.textContaining('cannot be booked'), findsOneWidget);
  });

  testWidgets('shop closed day and nobody working say so', (tester) async {
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 20, 6);
    final day = CalendarDay(
      lanes: _lanes.take(1).toList(),
      events: const [],
      availability: const DayAvailability(
        openMin: 540,
        closeMin: 1200,
        shopDayOff: true,
        staff: {},
      ),
    );
    await _pump(tester, day);
    expect(find.text('Shop is closed today'), findsOneWidget);
    expect(find.text('Nobody is working today.'), findsOneWidget);
  });
}
