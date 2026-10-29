import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/domain/day_timeline.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/calendar_legend.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/day_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/calendar_fixtures.dart';
import '../../helpers/load_fonts.dart';

/// Mike works 9-13 and 14-20, Mutaz 9-15 (a fixed "now" of 10:40).
const _availability = DayAvailability(
  openMin: 9 * 60,
  closeMin: 20 * 60,
  shopDayOff: false,
  staff: {
    42: StaffDay(isDayOff: false, hours: [(540, 780), (840, 1200)]),
    49: StaffDay(isDayOff: false, hours: [(540, 900)]),
  },
);

class _Taps {
  final slots = <(int, int)>[];
  final blocked = <(SlotVerdict, int, int)>[];
  final events = <String>[];
}

Future<_Taps> _grid(
  WidgetTester tester, {
  DayAvailability availability = _availability,
  Set<int> focus = const {},
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final taps = _Taps();
  final day = calendarWindow(
    '2026-10-25',
  ).day(DateTime(2026, 10, 25), availability);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: DayGrid(
          day: day,
          date: DateTime(2026, 10, 25),
          focus: focus,
          onEventTap: (e) => taps.events.add(e.title),
          onSlotTap: (l, m) => taps.slots.add((l, m)),
          onBlocked: (why, lane, m) => taps.blocked.add((why, lane.id, m)),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
  return taps;
}

/// Taps lane [laneIndex] at [hour]:[minute] (the grid starts at 9, 88 px an hour).
Future<void> _tapAt(
  WidgetTester tester,
  int laneIndex,
  int hour,
  int minute,
) async {
  final top = tester.getTopLeft(find.byType(DayGrid));
  final box = tester.getSize(find.byType(DayGrid));
  final laneW = (box.width - DayGrid.gutter) / 2;
  final label = tester.getCenter(
    find.text('${hour % 12 == 0 ? 12 : hour % 12} ${hour < 12 ? 'AM' : 'PM'}'),
  );
  // The label sits on the hour line; add the minutes.
  final y = label.dy + minute / 60 * DayGrid.hourHeight + 1;
  await tester.tapAt(
    Offset(top.dx + DayGrid.gutter + laneW * laneIndex + laneW / 2, y),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40); // 10:40 Edmonton
  });

  group('taps open a form only where a booking can go', () {
    testWidgets('a free spot is marked first; the form opens from the mark', (
      tester,
    ) async {
      final taps = await _grid(tester);
      await _tapAt(tester, 0, 12, 0); // Mike, 12:00 (free until 13:00)
      expect(taps.slots, isEmpty);
      expect(taps.blocked, isEmpty);
      expect(find.text('Book 12:00 PM'), findsOneWidget);
      await tester.tap(find.text('Book 12:00 PM'));
      await tester.pump();
      expect(taps.slots.single, (42, 12 * 60));
    });

    testWidgets('outside the working hours: not available, no form', (
      tester,
    ) async {
      final taps = await _grid(tester);
      await _tapAt(tester, 0, 13, 15); // Mike's gap between his two blocks
      expect(taps.slots, isEmpty);
      expect(taps.blocked.single.$1, SlotVerdict.unavailable);
      expect(taps.blocked.single.$2, 42);
      expect(find.textContaining('Book '), findsNothing);
    });

    testWidgets('an earlier time of today can still be booked (like the web)', (
      tester,
    ) async {
      final taps = await _grid(tester);
      await _tapAt(tester, 1, 10, 15); // Mutaz, 10:15, before 10:40
      expect(taps.blocked, isEmpty);
      expect(find.text('Book 10:15 AM'), findsOneWidget);
      await tester.tap(find.text('Book 10:15 AM'));
      await tester.pump();
      expect(taps.slots.single, (49, 10 * 60 + 15));
    });

    testWidgets('a break does not open the booking form', (tester) async {
      final taps = await _grid(tester);
      await tester.tap(find.textContaining('Break ·'));
      await tester.pump();
      expect(taps.blocked.single.$1, SlotVerdict.onBreak);
      expect(taps.slots, isEmpty);
    });

    testWidgets('a booking opens its details, not the form', (tester) async {
      final taps = await _grid(tester);
      await tester.tap(find.text('Daniel Okafor'));
      await tester.pump();
      expect(taps.events, ['Daniel Okafor']);
      expect(taps.slots, isEmpty);
    });

    testWidgets('tapping elsewhere moves the mark; a blocked spot clears it', (
      tester,
    ) async {
      final taps = await _grid(tester);
      await _tapAt(tester, 0, 12, 0);
      expect(find.text('Book 12:00 PM'), findsOneWidget);
      await _tapAt(tester, 1, 14, 30); // Mutaz, free 14:30
      expect(find.text('Book 12:00 PM'), findsNothing);
      expect(find.text('Book 2:30 PM'), findsOneWidget);
      await _tapAt(tester, 0, 13, 15); // not available
      expect(find.textContaining('Book '), findsNothing);
      expect(taps.slots, isEmpty);
    });

    testWidgets('a barber without working hours: whole column says so', (
      tester,
    ) async {
      final taps = await _grid(
        tester,
        availability: const DayAvailability(
          openMin: 540,
          closeMin: 1200,
          shopDayOff: false,
          staff: {
            42: StaffDay(isDayOff: false, hours: []),
            49: StaffDay(isDayOff: false, hours: [(540, 900)]),
          },
        ),
      );
      expect(find.text('No hours set'), findsOneWidget);
      await _tapAt(tester, 0, 15, 0);
      expect(taps.blocked.single.$1, SlotVerdict.unavailable);
      expect(taps.slots, isEmpty);
    });

    testWidgets('a day off and a closed shop', (tester) async {
      final off = await _grid(
        tester,
        availability: const DayAvailability(
          openMin: 540,
          closeMin: 1200,
          shopDayOff: false,
          staff: {
            42: StaffDay(isDayOff: true, hours: []),
            49: StaffDay(isDayOff: false, hours: [(540, 900)]),
          },
        ),
      );
      expect(find.text('Day off'), findsWidgets);
      await _tapAt(tester, 0, 15, 0);
      expect(off.blocked.single.$1, SlotVerdict.dayOff);
    });

    testWidgets('free time is written in the column', (tester) async {
      await _grid(tester);
      expect(find.textContaining('Free · '), findsWidgets);
      expect(find.text('Not available'), findsWidgets);
    });
  });

  group('legend', () {
    CalendarDay dayOf() =>
        calendarWindow('2026-10-25').day(DateTime(2026, 10, 25), _availability);

    testWidgets('counts only what has a column, per status', (tester) async {
      // Daniel (pending, Mike) and Ahmed (pending, JOJO: no column) -> 1.
      final c = DayCounts.of(dayOf());
      expect(c.of(0), 1);
      expect(c.of(3), 1); // Marcus
      expect(c.of(4), 1); // Sam
      expect(c.breaks, 1);
    });

    testWidgets('a status chip keeps those bookings bright', (tester) async {
      var focus = <int>{};
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => CalendarLegend(
                counts: DayCounts.of(dayOf()),
                focus: focus,
                onFocus: (f) => set(() => focus = f),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Confirmed'), findsOneWidget);
      expect(find.text('Rescheduled'), findsOneWidget);
      await tester.tap(find.text('Pending'));
      await tester.pump();
      expect(focus, {0});
      await tester.tap(find.text('Pending'));
      await tester.pump();
      expect(focus, isEmpty);
    });

    testWidgets('the guide explains every colour', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCalendarGuide(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('How to read the calendar'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('Break'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });
  });
}
