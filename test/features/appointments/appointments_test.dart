import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/application/appointments_controller.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/domain/appointment.dart';
import 'package:barbershop_app/features/appointments/presentation/appointments_page.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/appointment_fixtures.dart';
import '../../helpers/auth_fixtures.dart';
import '../../helpers/calendar_fixtures.dart';
import '../../helpers/home_fixtures.dart';
import '../../helpers/load_fonts.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

Future<(FakeAppointmentsRepo, ProviderContainer)> _pump(
  WidgetTester tester,
  Widget page, {
  int detailStatus = 0,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeAppointmentsRepo(detailStatus: detailStatus);
  final container = ProviderContainer(
    overrides: [
      bootstrapProvider.overrideWithValue(adminBootstrap()),
      currentUserProvider.overrideWithValue(adminBootstrap().user),
      appointmentsRepositoryProvider.overrideWithValue(repo),
      customersRepositoryProvider.overrideWithValue(FakeCustomersRepo()),
      homeProvider.overrideWith(() => FixedHome(adminHomeRaw())),
      calendarProvider.overrideWith(
        () => FixedCalendar(calendarWindow('2026-10-25')),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark, home: page),
    ),
  );
  await _settle(tester);
  return (repo, container);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  group('AppointmentFilter', () {
    test('query only has what is set (the server needs both dates)', () {
      expect(const AppointmentFilter().toQuery(), isEmpty);
      final f = const AppointmentFilter().copyWith(
        status: AppointmentStatus.confirmed,
        startDate: '2026-10-26',
        endDate: '2026-10-27',
        staffId: 42,
        dayType: 'Morning',
        query: '  luke ',
      );
      expect(f.toQuery(), {
        'status': 3,
        'start_date': '2026-10-26',
        'end_date': '2026-10-27',
        'staff_id': 42,
        'day_type': 'Morning',
        'q': 'luke',
      });
      expect(f.activeCount, 3);
      // One date alone is not sent.
      expect(
        const AppointmentFilter(startDate: '2026-10-26').toQuery(),
        isEmpty,
      );
    });

    test('copyWith can clear a value with null', () {
      const f = AppointmentFilter(staffId: 4, dayType: 'Evening');
      final g = f.copyWith(staffId: null);
      expect(g.staffId, isNull);
      expect(g.dayType, 'Evening');
    });
  });

  group('parsing', () {
    test('detail uses the grouped services and barbers', () {
      final d = AppointmentDetail.fromJson(detailJson());
      expect(d.row.customerName, 'Luke Tremblay');
      expect(d.services.map((s) => s.name), [
        "Men's cut",
        'Beard (trim line up)',
      ]);
      expect(d.totalMinutes, 45);
      expect(d.total.toApi(), '50.00');
      expect(d.barbers, ['Mutaz']);
      expect(d.customerEmail, 'luke@example.com');
    });

    test('counts map to statuses', () {
      final c = AppointmentCounts.fromJson({
        'counts': {
          'all': 33,
          'pending': 16,
          'confirmed': 0,
          'completed': 17,
          'cancelled': 0,
          'rescheduled': 0,
        },
      });
      expect(c.forStatus(null), 33);
      expect(c.forStatus(AppointmentStatus.completed), 17);
    });
  });

  group('Bookings list', () {
    testWidgets('shows days, customers and status counts', (tester) async {
      await _pump(tester, const AppointmentsPage());
      expect(find.text('Ben Carter'), findsOneWidget);
      expect(find.text('Daniel Okafor'), findsOneWidget);
      expect(find.text('TOMORROW'), findsOneWidget);
      expect(find.text('2'), findsWidgets); // pending count chip
      expect(find.text('Confirm'), findsWidgets);
    });

    testWidgets('a status chip reloads with that status', (tester) async {
      final (repo, container) = await _pump(tester, const AppointmentsPage());
      await tester.tap(find.text('Pending').first);
      await _settle(tester);
      expect(
        container.read(appointmentFilterProvider).status,
        AppointmentStatus.pending,
      );
      expect(repo.filters.last.status, AppointmentStatus.pending);
      expect(find.text('Luke Tremblay'), findsNothing);
      expect(find.text('Ben Carter'), findsOneWidget);
    });

    testWidgets('search sends the text after the user stops typing', (
      tester,
    ) async {
      final (repo, _) = await _pump(tester, const AppointmentsPage());
      await tester.tap(find.byIcon(Icons.search_rounded));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText).first, 'luke');
      await tester.pump(const Duration(milliseconds: 600));
      await _settle(tester);
      expect(repo.filters.last.query, 'luke');
      expect(find.text('Luke Tremblay'), findsOneWidget);
      expect(find.text('Ben Carter'), findsNothing);
    });

    testWidgets('the filter sheet applies a date range and shows the count', (
      tester,
    ) async {
      final (_, container) = await _pump(tester, const AppointmentsPage());
      await tester.tap(find.byIcon(Icons.tune_rounded));
      await _settle(tester);
      expect(find.text('Day Type'.toUpperCase()), findsOneWidget);
      await tester.tap(find.text('Tomorrow'));
      await tester.pump();
      await tester.tap(find.text('Evening'));
      await tester.pump();
      await tester.tap(find.text('Show results'));
      await _settle(tester);
      final f = container.read(appointmentFilterProvider);
      expect(f.startDate, '2026-10-26');
      expect(f.endDate, '2026-10-26');
      expect(f.dayType, 'Evening');
      expect(
        find.descendant(
          of: find.byType(HeaderIconButton),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('empty result says so', (tester) async {
      await _pump(tester, const AppointmentsPage());
      await tester.tap(find.byIcon(Icons.search_rounded));
      await _settle(tester);
      await tester.enterText(find.byType(EditableText).first, 'zzzz');
      await tester.pump(const Duration(milliseconds: 600));
      await _settle(tester);
      expect(find.text('No bookings found'), findsOneWidget);
    });
  });

  group('Appointment sheet', () {
    Future<FakeAppointmentsRepo> open(
      WidgetTester tester, {
      int status = 0,
    }) async {
      final (repo, _) = await _pump(
        tester,
        const AppointmentsPage(),
        detailStatus: status,
      );
      await tester.tap(find.text('Luke Tremblay'));
      await _settle(tester);
      return repo;
    }

    // The sheet is taller than its first stop: scroll its content.
    Future<void> scrollSheet(WidgetTester tester) async {
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await _settle(tester);
    }

    testWidgets('shows the customer and everything the web shows', (
      tester,
    ) async {
      await open(tester);
      // contact row + quick buttons (top of the sheet)
      expect(find.textContaining('7805550106'), findsWidgets);
      expect(find.text('Call'), findsOneWidget);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      await scrollSheet(tester);
      expect(find.text('Appointment Details'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Tuesday, 27 Oct 2026'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.textContaining('10:00 AM - 10:45 AM'), findsWidgets);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Services'), findsOneWidget);
      expect(find.text("Men's cut"), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text(r'$50.00'), findsOneWidget);
      await scrollSheet(tester);
      expect(find.text('Prefers a number 2 on the sides.'), findsOneWidget);
    });

    testWidgets('customer facts come from the customer record', (tester) async {
      await open(tester);
      expect(find.text('Visits'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Appointments'), findsWidgets);
      expect(find.text('9'), findsOneWidget);
    });

    testWidgets(
      'pending: Confirm, Reschedule and Cancel, in the web\'s words',
      (tester) async {
        final repo = await open(tester);
        expect(find.widgetWithText(AppButton, 'Confirm'), findsOneWidget);
        expect(find.widgetWithText(AppButton, 'Reschedule'), findsOneWidget);
        expect(find.widgetWithText(AppButton, 'Cancel'), findsOneWidget);
        await tester.tap(find.widgetWithText(AppButton, 'Confirm'));
        await _settle(tester);
        expect(repo.calls, contains('confirm:4'));
      },
    );

    testWidgets('Cancel asks first, with the web\'s question', (tester) async {
      final repo = await open(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
      await _settle(tester);
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(find.text('Are you sure to cancel order?'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('cancel')), isEmpty);
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(repo.calls, contains('cancel:4'));
    });

    testWidgets('Reschedule: needs a slot, then sends date and times', (
      tester,
    ) async {
      final repo = await open(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Reschedule'));
      await _settle(tester);
      expect(find.text('Reschedule Appointment'), findsOneWidget);
      expect(find.text('Select Time'), findsOneWidget);
      // The finder is asked for this booking's barber and services.
      expect(
        repo.calls.any((c) => c.startsWith('slots:2026-10-27:49:25,33')),
        isTrue,
      );
      expect(find.text('MORNING'), findsOneWidget);
      expect(find.text('AFTERNOON'), findsOneWidget);
      expect(find.text('EVENING'), findsOneWidget);

      // No slot chosen: the web's message, no request.
      await tester.tap(find.widgetWithText(AppButton, 'Reschedule'));
      await _settle(tester);
      expect(find.text('Please Select Slot!!'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('reschedule')), isEmpty);

      await tester.tap(find.text('01:30 PM'));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Reschedule'));
      await _settle(tester);
      expect(repo.calls, contains('reschedule:4:2026-10-27:13:30-14:00'));
    });

    testWidgets('a confirmed booking can only be cancelled', (tester) async {
      await open(tester, status: 3);
      expect(find.widgetWithText(AppButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Confirm'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Reschedule'), findsNothing);
    });

    testWidgets('a completed booking has no action buttons', (tester) async {
      await open(tester, status: 1);
      expect(find.widgetWithText(AppButton, 'Confirm'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Cancel'), findsNothing);
      expect(find.widgetWithText(AppButton, 'Reschedule'), findsNothing);
    });

    // The web's buttons per status, in the web's order.
    for (final (status, expected) in [
      (0, ['Confirm', 'Complete', 'Cancel', 'Reschedule']),
      (3, ['Cancel', 'Complete']),
      (4, ['Confirm', 'Complete', 'Cancel']),
      (2, ['Reschedule']),
      (1, <String>[]),
    ]) {
      testWidgets('status $status shows exactly $expected', (tester) async {
        await open(tester, status: status);
        final labels = find
            .byType(AppButton)
            .evaluate()
            .map((e) => (e.widget as AppButton).label)
            .toList();
        expect(labels, expected);
      });
    }

    testWidgets('Edit (pencil) is offered on open bookings only', (
      tester,
    ) async {
      await open(tester, status: 0);
      expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
    });

    testWidgets('no Edit on a completed booking', (tester) async {
      await open(tester, status: 1);
      expect(find.byIcon(Icons.edit_rounded), findsNothing);
    });
  });
}
