import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/network/api_client.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/data/calendar_repository.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/presentation/calendar_page.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/day_grid.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/calendar_fixtures.dart';
import '../../helpers/home_fixtures.dart';
import '../../helpers/load_fonts.dart';

class _FakeAppointments extends AppointmentsRepository {
  _FakeAppointments() : super(_NoApi());

  final calls = <String>[];
  Failure? failure;

  @override
  Future<void> confirm(int id) async {
    calls.add('confirm:$id');
    if (failure != null) throw failure!;
  }

  @override
  Future<void> cancel(int id) async {
    calls.add('cancel:$id');
    if (failure != null) throw failure!;
  }
}

class _NoApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeCalendarRepo extends CalendarRepository {
  _FakeCalendarRepo() : super(_NoApi());

  final breaks = <String>[];

  @override
  Future<void> addBreak({
    required int staffId,
    bool restOfDay = false,
    int hours = 0,
    int minutes = 0,
  }) async {
    breaks.add('$staffId:$restOfDay:$hours:$minutes');
  }
}

Future<(FixedCalendar, _FakeAppointments, _FakeCalendarRepo)> _pump(
  WidgetTester tester, {
  DayAvailability? availability,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final cal = FixedCalendar(calendarWindow('2026-10-25'));
  final appts = _FakeAppointments();
  final calRepo = _FakeCalendarRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(adminBootstrap()),
        currentUserProvider.overrideWithValue(adminBootstrap().user),
        calendarProvider.overrideWith(() => cal),
        appointmentsRepositoryProvider.overrideWithValue(appts),
        calendarRepositoryProvider.overrideWithValue(calRepo),
        homeProvider.overrideWith(() => FixedHome(adminHomeRaw())),
        dayAvailabilityProvider.overrideWith(
          (ref, date) async => availability ?? DayAvailability.fallback(),
        ),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const CalendarPage()),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
  return (cal, appts, calRepo);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40); // 10:40 Edmonton
  });

  group('models', () {
    test('events parse the real API shape', () {
      final w = calendarWindow('2026-10-25');
      final a = w.events.first;
      expect(a.title, 'Marcus Lee');
      expect(a.startMin, 10 * 60);
      expect(a.endMin, 10 * 60 + 30);
      expect(a.laneId, 42);
      expect(a.appointmentId, 1);
      expect(w.events.last.isBreak, isTrue);
    });

    test('only barber lanes are columns, like the web', () {
      final w = calendarWindow('2026-10-25');
      final day = w.day(ShopTime.today(), DayAvailability.fallback());
      expect(day.lanes.map((l) => l.id), [42, 49]);
      // The booking of a non-barber is in the data but has no column.
      expect(day.events.any((e) => e.laneId == 47), isTrue);
    });

    test('busy days mark appointments, not breaks', () {
      final w = calendarWindow('2026-10-25');
      expect(w.busyDays, {DateTime(2026, 10, 25)});
    });

    test('availability: working blocks and day off', () {
      final a = DayAvailability.fromJson({
        'shop_open': '09:00',
        'shop_close': '20:00',
        'shop_day_off': false,
        'staff': {
          '49': {
            'is_day_off': false,
            'working_hours': [
              {'start': '09:00', 'end': '13:00'},
            ],
            'breaks': [],
          },
          '51': {'is_day_off': true, 'working_hours': [], 'breaks': []},
        },
      });
      expect(a.openMin, 540);
      expect(a.closeMin, 1200);
      expect(a.staff[49]!.hours, [(540, 780)]);
      expect(a.staff[51]!.isDayOff, isTrue);
    });
  });

  group('Calendar screen', () {
    testWidgets('shows barber columns, bookings, the break and the now line', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Mike'), findsOneWidget);
      expect(find.text('Mutaz'), findsOneWidget);
      expect(find.text('Marcus Lee'), findsOneWidget);
      expect(find.text('Daniel Okafor'), findsOneWidget);
      expect(find.textContaining('Break ·'), findsOneWidget);
      expect(find.text('10:40AM'), findsOneWidget); // the now badge
      expect(find.textContaining('2 booked'), findsOneWidget);
      // The way into the wide landscape view.
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    });

    testWidgets('tapping a booking opens details; Confirm calls the API', (
      tester,
    ) async {
      final (_, appts, _) = await _pump(tester);
      await tester.tap(find.text('Daniel Okafor'));
      await _settle(tester);
      expect(find.text('Appointment Details'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Confirm'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Reschedule'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Confirm'));
      await _settle(tester);
      expect(appts.calls, ['confirm:2']);
    });

    testWidgets('a confirmed booking offers Cancel only, never Confirm', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Marcus Lee'));
      await _settle(tester);
      expect(find.widgetWithText(AppButton, 'Confirm'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Reschedule'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('Cancel asks first, then cancels', (tester) async {
      final (_, appts, _) = await _pump(tester);
      await tester.tap(find.text('Marcus Lee'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await _settle(tester);
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(find.text('Are you sure to cancel order?'), findsOneWidget);
      expect(appts.calls, isEmpty);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(appts.calls, ['cancel:1']);
    });

    testWidgets('a 409 from the server shows its message', (tester) async {
      final (_, appts, _) = await _pump(tester);
      appts.failure = const ConflictFailure('Already confirmed.');
      await tester.tap(find.text('Daniel Okafor'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Confirm'));
      await _settle(tester);
      expect(find.text('Already confirmed.'), findsOneWidget);
    });

    testWidgets('Add break: choose a barber, then save', (tester) async {
      final (_, _, repo) = await _pump(tester);
      await tester.tap(
        find.widgetWithIcon(HeaderIconButton, Icons.coffee_rounded),
      );
      await _settle(tester);
      expect(find.text('Add a break'), findsOneWidget);
      await tester.tap(find.text('Mutaz').last);
      await tester.pump();
      await tester.tap(find.text('45 min'));
      await tester.pump();
      await tester.tap(find.text('Add break').last);
      await _settle(tester);
      expect(repo.breaks, ['49:false:0:45']);
    });

    testWidgets('shop closed banner', (tester) async {
      await _pump(
        tester,
        availability: const DayAvailability(
          openMin: 540,
          closeMin: 1200,
          shopDayOff: true,
          staff: {},
        ),
      );
      expect(find.text('The shop is closed on this day.'), findsOneWidget);
    });

    testWidgets('tapping an empty spot gives the barber and a quarter hour', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final taps = <(int, int)>[];
      final day = calendarWindow('2026-10-25').day(
        DateTime(2026, 10, 25),
        const DayAvailability(
          openMin: 9 * 60,
          closeMin: 20 * 60,
          shopDayOff: false,
          staff: {},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: DayGrid(
              day: day,
              date: DateTime(2026, 10, 25),
              onEventTap: (_) {},
              onSlotTap: (lane, minutes) => taps.add((lane, minutes)),
            ),
          ),
        ),
      );
      await _settle(tester);
      // Mike's column starts right of the time axis; 3 PM is free there.
      final top = tester.getTopLeft(find.byType(DayGrid));
      final label = tester.getCenter(find.text('3 PM'));
      await tester.tapAt(
        Offset(top.dx + DayGrid.gutter + 40, label.dy + 22),
      ); // 3:15 PM
      await tester.pump();
      // The first tap only marks the spot (no form yet) ...
      expect(taps, isEmpty);
      expect(find.text('Book 3:15 PM'), findsOneWidget);
      // ... the tap on the mark opens it.
      await tester.tap(find.text('Book 3:15 PM'));
      await tester.pump();
      expect(taps.single.$1, 42);
      expect(taps.single.$2, 15 * 60 + 15);
    });

    testWidgets('Filter by Staff shows one barber, All Staff shows everyone', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Mutaz'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.groups_rounded));
      await _settle(tester);
      expect(find.text('All Staff'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppChoiceChip, 'Mike'));
      await _settle(tester);
      expect(find.text('Mutaz'), findsNothing);
      expect(find.text('Mike'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.groups_rounded));
      await _settle(tester);
      await tester.tap(find.text('All Staff'));
      await _settle(tester);
      expect(find.text('Mutaz'), findsOneWidget);
    });
    testWidgets('dragging a barber in the sheet reorders the columns', (
      tester,
    ) async {
      await _pump(tester);
      final before = tester.getTopLeft(find.text('Mike')).dx;
      expect(before, lessThan(tester.getTopLeft(find.text('Mutaz')).dx));

      await tester.tap(find.byIcon(Icons.groups_rounded));
      await _settle(tester);
      expect(find.text('Column order'), findsOneWidget);
      final handles = find.byIcon(Icons.drag_handle_rounded);
      expect(handles, findsNWidgets(2));
      final g = await tester.startGesture(tester.getCenter(handles.first));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await _settle(tester);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      expect(container.read(calendarOrderProvider), [49, 42]);
    });
  });

  group('orderLanes', () {
    test('ordered ids first, the rest keep their place', () {
      final w = calendarWindow('2026-10-25');
      final lanes = w.day(ShopTime.today(), DayAvailability.fallback()).lanes;
      expect(orderLanes(lanes, const []).map((l) => l.id), [42, 49]);
      expect(orderLanes(lanes, const [49]).map((l) => l.id), [49, 42]);
      expect(orderLanes(lanes, const [99, 49, 42]).map((l) => l.id), [49, 42]);
    });
  });
}
