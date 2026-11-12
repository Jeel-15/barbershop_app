import 'dart:async';

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/application/booking_form_controller.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/presentation/booking_form_page.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/appointment_fixtures.dart';
import '../../helpers/auth_fixtures.dart';
import '../../helpers/calendar_fixtures.dart';
import '../../helpers/load_fonts.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

Future<FakeAppointmentsRepo> _open(
  WidgetTester tester,
  BookingTarget target,
) async {
  tester.view.physicalSize = const Size(390 * 3, 2200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeAppointmentsRepo();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(
        path: '/form',
        builder: (_, _) => BookingFormPage(target: target),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(adminBootstrap()),
        currentUserProvider.overrideWithValue(adminBootstrap().user),
        appointmentsRepositoryProvider.overrideWithValue(repo),
        customersRepositoryProvider.overrideWithValue(FakeCustomersRepo()),
        calendarProvider.overrideWith(
          () => FixedCalendar(calendarWindow('2026-10-25')),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await _settle(tester);
  unawaited(router.push('/form'));
  await _settle(tester);
  return repo;
}

/// Opens the picker, taps a service, closes it.
/// The save button now says "Review ...": it opens the check sheet, and Done in
/// the sheet is what saves.
Future<void> _reviewAndSave(
  WidgetTester tester, {
  String button = 'Review appointment',
}) async {
  await tester.tap(find.widgetWithText(AppButton, button));
  await _settle(tester);
  await tester.tap(find.widgetWithText(AppButton, 'Done'));
  await _settle(tester);
}

Future<void> _pick(WidgetTester tester, String service, {int times = 1}) async {
  await tester.tap(find.text('Select Service').last);
  await _settle(tester);
  for (var i = 0; i < times; i++) {
    await tester.tap(find.text(service).last);
    await tester.pump();
  }
  await tester.tap(find.text('Done'));
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  group('Add Appointment', () {
    testWidgets('has the web\'s fields', (tester) async {
      await _open(tester, const BookingTarget());
      expect(find.text('Add Appointment'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Full Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Service'), findsOneWidget);
      // Staff, Date and Time are on the form from the start, like the web.
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
      expect(find.text('Select Time'), findsOneWidget);
      expect(find.text('Choose time'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Select Service'), findsOneWidget);
      expect(find.text('Review appointment'), findsOneWidget);
    });

    testWidgets(
      'Staff lists every barber first, then only those who do the service',
      (tester) async {
        final repo = await _open(tester, const BookingTarget());
        // No service yet: every barber of the calendar (the web does the same).
        expect(find.text('Mike'), findsOneWidget);
        expect(find.text('Mutaz'), findsOneWidget);

        await _pick(tester, "Men's cut");
        expect(repo.calls, contains('barbers:25'));
        expect(find.text('mike'), findsOneWidget);
        expect(find.text('Mutaz'), findsOneWidget);

        await tester.tap(find.text('mike'));
        await _settle(tester);
        expect(
          repo.calls.any((c) => c.startsWith('slots:2026-10-25:42:25')),
          isTrue,
        );
        expect(find.text('09:30 AM'), findsOneWidget);
      },
    );

    testWidgets('a time can be chosen by hand, without any slot list', (
      tester,
    ) async {
      final repo = await _open(tester, const BookingTarget());
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Full Name'),
        'Ravi',
      );
      await tester.enterText(find.widgetWithText(AppTextField, 'Phone'), '780');
      await _pick(tester, "Men's cut");
      await tester.tap(find.text('Mutaz'));
      await _settle(tester);
      // The "Choose time" dialog is the platform's; set the time the way it would.
      final c = ProviderScope.containerOf(
        tester.element(find.byType(BookingFormPage)),
      );
      c
          .read(bookingFormProvider(const BookingTarget()).notifier)
          .setCustomTime(10, 40);
      await _settle(tester);
      expect(find.text('Time: 10:40 AM'), findsOneWidget);
      await _reviewAndSave(tester);
      expect(repo.created.single.toJson()['time'], '10:40');
    });

    testWidgets('a tapped calendar slot prefills barber, day and time', (
      tester,
    ) async {
      final repo = await _open(
        tester,
        const BookingTarget(staffId: 42, date: '2026-10-26', time: '09:30'),
      );
      await _pick(tester, "Men's cut");
      expect(
        repo.calls.any((c) => c.startsWith('slots:2026-10-26:42:25')),
        isTrue,
      );
      // 09:30 is offered, so it is already chosen: the bar shows it.
      expect(find.textContaining('09:30 AM'), findsWidgets);
    });

    testWidgets('saves exactly what was entered', (tester) async {
      final repo = await _open(tester, const BookingTarget());
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Full Name'),
        'Ravi Shah',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Phone'),
        '7805559999',
      );
      await _pick(tester, "Men's cut", times: 2); // quantity 2
      await tester.tap(find.text('Mutaz'));
      await _settle(tester);
      await tester.tap(find.text('01:30 PM'));
      await tester.pump();
      await _reviewAndSave(tester);

      expect(repo.created, hasLength(1));
      final b = repo.created.single;
      expect(b.toJson(), {
        'date': '2026-10-25',
        'time': '13:30',
        'staff_id': 49,
        'services': [
          {'id': 25, 'qty': 2},
        ],
        'name': 'Ravi Shah',
        'phone': '7805559999',
      });
      expect(find.text('BACK'), findsOneWidget);
    });

    testWidgets('Review shows what will be saved; Edit keeps the form, Done '
        'saves', (tester) async {
      final repo = await _open(tester, const BookingTarget());
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Full Name'),
        'Ravi Shah',
      );
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Phone'),
        '7805559999',
      );
      await _pick(tester, "Men's cut", times: 2);
      await tester.tap(find.text('Mutaz'));
      await _settle(tester);
      await tester.tap(find.text('01:30 PM'));
      await tester.pump();

      await tester.tap(find.widgetWithText(AppButton, 'Review appointment'));
      await _settle(tester);
      expect(find.text('Check the booking'), findsOneWidget);
      expect(find.text('Ravi Shah'), findsWidgets);
      expect(find.text('7805559999'), findsWidgets);
      expect(find.text("Men's cut x 2"), findsOneWidget);
      expect(find.text('Mutaz'), findsWidgets);
      expect(find.text('01:30 PM'), findsWidgets);
      // Nothing is saved yet.
      expect(repo.created, isEmpty);

      // Edit: back to the form, everything still filled in.
      await tester.tap(find.widgetWithText(AppButton, 'Edit'));
      await _settle(tester);
      expect(find.text('Check the booking'), findsNothing);
      expect(repo.created, isEmpty);
      expect(find.text('Ravi Shah'), findsOneWidget);

      // Review again, then Done.
      await _reviewAndSave(tester);
      expect(repo.created, hasLength(1));
    });

    testWidgets('missing pieces are named, nothing is sent', (tester) async {
      final repo = await _open(tester, const BookingTarget());
      await tester.tap(find.widgetWithText(AppButton, 'Review appointment'));
      await _settle(tester);
      expect(find.text('Full Name is required.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Full Name'),
        'Ravi',
      );
      await tester.enterText(find.widgetWithText(AppTextField, 'Phone'), '780');
      await tester.tap(find.widgetWithText(AppButton, 'Review appointment'));
      await _settle(tester);
      expect(find.text('Please select at least one service.'), findsOneWidget);
      expect(repo.created, isEmpty);
    });

    testWidgets('an existing customer can be picked from the suggestions', (
      tester,
    ) async {
      await _open(tester, const BookingTarget());
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Phone'),
        '78055',
      );
      await _settle(tester);
      expect(find.textContaining('Sam Patel'), findsOneWidget);
      await tester.tap(find.textContaining('Sam Patel'));
      await _settle(tester);
      expect(find.text('Sam Patel'), findsOneWidget); // in the name field
      expect(find.text('7805550103'), findsOneWidget);
      expect(find.text('sam@example.com'), findsOneWidget);
    });
  });

  group('Update Appointment', () {
    testWidgets('opens with the booking filled in and keeps its own time', (
      tester,
    ) async {
      final repo = await _open(tester, const BookingTarget(editId: 4));
      expect(find.text('Update Appointment'), findsOneWidget);
      expect(find.text('Luke Tremblay'), findsOneWidget);
      expect(find.text('7805550106'), findsOneWidget);
      expect(find.text("Men's cut"), findsOneWidget);
      expect(find.text('Beard (trim line up)'), findsOneWidget);
      // Mutaz does the services: asked for with both service ids.
      expect(repo.calls, contains('barbers:25,33'));
      // The booking's own 10:00 AM is offered even though the finder calls it taken.
      expect(find.text('10:00 AM'), findsOneWidget);

      await _reviewAndSave(tester, button: 'Review changes');
      expect(repo.updated, hasLength(1));
      final (id, b) = repo.updated.single;
      expect(id, 4);
      expect(b.toJson()['time'], '10:00');
      expect(b.toJson()['staff_id'], 49);
    });
  });
}
