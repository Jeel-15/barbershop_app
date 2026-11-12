import 'dart:async';

import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/features/pos/data/pos_repository.dart';
import 'package:barbershop_app/features/pos/domain/pos_models.dart';
import 'package:barbershop_app/features/pos/presentation/invoice_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/appointment_fixtures.dart';
import '../../helpers/auth_fixtures.dart';
import '../../helpers/calendar_fixtures.dart';
import '../../helpers/home_fixtures.dart';
import '../../helpers/load_fonts.dart';
import '../../helpers/pos_fixtures.dart';

/// The save button now says "Review ...": it opens the check sheet, and Done in
/// the sheet is what saves.
Future<void> _reviewAndSubmit(WidgetTester tester, String button) async {
  await tester.tap(find.widgetWithText(AppButton, button));
  await _settle(tester);
  await tester.tap(find.widgetWithText(AppButton, 'Done'));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

Future<FakePosRepo> _open(WidgetTester tester, {int? appointmentId}) async {
  tester.view.physicalSize = const Size(390 * 3, 2000 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final pos = FakePosRepo();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(
        path: '/invoice',
        builder: (_, _) => InvoiceFormPage(appointmentId: appointmentId),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(adminBootstrap()),
        currentUserProvider.overrideWithValue(adminBootstrap().user),
        posRepositoryProvider.overrideWithValue(pos),
        appointmentsRepositoryProvider.overrideWithValue(
          FakeAppointmentsRepo(),
        ),
        homeProvider.overrideWith(() => FixedHome(adminHomeRaw())),
        calendarProvider.overrideWith(
          () => FixedCalendar(calendarWindow('2026-10-25')),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await _settle(tester);
  unawaited(router.push('/invoice'));
  await _settle(tester);
  return pos;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  group('Complete (an appointment)', () {
    testWidgets('opens prefilled: customer, services, barber and the total', (
      tester,
    ) async {
      await _open(tester, appointmentId: 4);
      expect(find.text('Complete'), findsWidgets);
      expect(find.text('Customer Information'), findsOneWidget);
      expect(find.text('Luke Tremblay'), findsWidgets);
      expect(find.text("Men's cut"), findsOneWidget);
      expect(find.text('Beard (trim line up)'), findsOneWidget);
      // Both lines come with their barber (Mutaz), so the server can total them.
      expect(find.text('Select Staff Members'), findsNothing);
      expect(find.text('Total Services Amount'), findsOneWidget);
      expect(find.text(r'$50.00'), findsWidgets);
    });

    testWidgets('sends the cart to the complete endpoint, then closes', (
      tester,
    ) async {
      final pos = await _open(tester, appointmentId: 4);
      await _reviewAndSubmit(tester, 'Review & complete');
      expect(pos.calls, ['complete:4']);
      final d = pos.drafts.single;
      expect(d.lines.map((l) => (l.id, l.staffId, l.qty)), [
        (25, 49, 1),
        (33, 49, 1),
      ]);
      expect(d.paymentMethod, 'Cash');
      expect(find.text('BACK'), findsOneWidget);
    });

    testWidgets('discount and tip change the total (server arithmetic)', (
      tester,
    ) async {
      await _open(tester, appointmentId: 4);
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Service Discount (%)'),
        '10',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await _settle(tester);
      expect(find.text('Service Discount (10%)'), findsOneWidget);
      expect(find.text(r'-$5.00'), findsOneWidget);
      // total = 50 - 5 = 45
      expect(find.text(r'$45.00'), findsWidgets);

      await tester.tap(find.text('20%'));
      await _settle(tester);
      // 20% of the 45.00 subtotal = 9.00
      expect(find.text(r'$54.00'), findsWidgets);
    });

    testWidgets('Review shows what will be saved; Edit changes nothing, Done '
        'saves', (tester) async {
      final pos = await _open(tester, appointmentId: 4);
      await tester.tap(find.widgetWithText(AppButton, 'Review & complete'));
      await _settle(tester);
      expect(find.text('Check the invoice'), findsOneWidget);
      expect(find.text('CUSTOMER'), findsOneWidget);
      expect(find.text('SERVICES'), findsOneWidget);
      expect(find.text('PAYMENT'), findsOneWidget);
      expect(find.text('Total Amount'), findsWidgets);
      expect(find.text('with Mutaz'), findsWidgets);
      // Nothing is saved while the sheet is open.
      expect(pos.calls, isEmpty);

      await tester.tap(find.widgetWithText(AppButton, 'Edit'));
      await _settle(tester);
      expect(find.text('Check the invoice'), findsNothing);
      expect(pos.calls, isEmpty);

      await _reviewAndSubmit(tester, 'Review & complete');
      expect(pos.calls, ['complete:4']);
    });

    testWidgets('payment method is chosen from the shop\'s methods', (
      tester,
    ) async {
      final pos = await _open(tester, appointmentId: 4);
      await tester.tap(find.text('Debit'));
      await tester.pump();
      await _reviewAndSubmit(tester, 'Review & complete');
      expect(pos.drafts.single.paymentMethod, 'Debit');
    });
  });

  group('Create Invoice (blank)', () {
    testWidgets('starts empty and cannot be saved without items', (
      tester,
    ) async {
      final pos = await _open(tester);
      expect(find.text('Create Invoice'), findsWidgets);
      expect(find.text('Phone Number'), findsOneWidget);
      expect(
        find.textContaining('Click on a service to select it'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(AppButton, 'Review invoice'));
      await _settle(tester);
      expect(find.textContaining('at least one service'), findsOneWidget);
      expect(pos.calls, isEmpty);
    });

    testWidgets(
      'a known phone number shows the customer card and fills the form',
      (tester) async {
        final pos = await _open(tester);
        await tester.enterText(
          find.widgetWithText(AppTextField, 'Phone Number'),
          '780555010',
        );
        await _settle(tester);
        expect(pos.calls.any((c) => c.startsWith('lookup:')), isFalse);

        await tester.enterText(
          find.widgetWithText(AppTextField, 'Phone Number'),
          '7805550103',
        );
        await _settle(tester);
        expect(find.text('Customer : Sam Patel'), findsOneWidget);
        expect(find.text('Total Visit : 3'), findsOneWidget);
        expect(find.text('Last Service : Skin fade'), findsOneWidget);
        expect(find.textContaining('Total Spend'), findsOneWidget);

        await tester.tap(find.text('Customer : Sam Patel'));
        await _settle(tester);
        expect(find.text('sam@example.com'), findsOneWidget);
      },
    );

    testWidgets('add a service, pick the barber, save', (tester) async {
      final pos = await _open(tester);
      await tester.tap(find.text('Add Services'));
      await _settle(tester);
      expect(find.text('Select Services'), findsOneWidget);
      // The picker sheet is on top, so its rows are the last matches.
      await tester.tap(find.text("Men's cut").last);
      await tester.pump();
      await tester.tap(
        find.text("Men's cut").last,
      ); // a second tap = quantity 2
      await tester.pump();
      await tester.tap(find.text('Done'));
      await _settle(tester);

      // No barber yet: the web's wording, and no total.
      expect(find.text('Select Staff Members'), findsWidgets);
      await tester.tap(find.widgetWithText(AppButton, 'Review invoice'));
      await _settle(tester);
      expect(pos.calls, isEmpty);
      // Let the error toast go away so it does not cover the button.
      await tester.pump(const Duration(seconds: 6));

      await tester.tap(find.text('mike'));
      await _settle(tester);
      expect(find.text(r'$60.00'), findsWidgets); // 2 x 30.00
      await _reviewAndSubmit(tester, 'Review invoice');
      expect(pos.calls, ['create']);
      final l = pos.drafts.single.lines.single;
      expect((l.id, l.qty, l.staffId), (25, 2, 42));
    });

    testWidgets('products are added the same way', (tester) async {
      await _open(tester);
      await tester.tap(find.text('Add Products'));
      await _settle(tester);
      expect(find.text('Select Products'), findsOneWidget);
      expect(find.textContaining('10 in stock'), findsOneWidget);
      await tester.tap(find.text('Hair oil'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await _settle(tester);
      expect(find.text('Hair oil'), findsOneWidget);
      expect(find.text('Product Discount (%)'), findsOneWidget);
    });
  });

  group('models', () {
    test('cart sends only what is set and keeps money exact', () {
      const d = InvoiceDraft(
        customerName: ' Sam ',
        lines: [
          InvoiceLine(
            type: LineType.service,
            id: 25,
            name: "Men's cut",
            price: Money(3000),
            qty: 2,
            staffId: 42,
          ),
        ],
        serviceDiscount: 10,
        tip: Money(550),
        paymentMethod: 'Cash',
      );
      final cart = d.toCart();
      expect(cart['tip'], '5.50');
      expect(cart['customer'], {'name': 'Sam'});
      expect((cart['items'] as List).single, {
        'type': 'service',
        'id': 25,
        'staff_id': 42,
        'qty': 2,
      });
      // Completing keeps the appointment's own customer.
      expect(d.toCart(withCustomer: false).containsKey('customer'), isFalse);
    });
  });
}
