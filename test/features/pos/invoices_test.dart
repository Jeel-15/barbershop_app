import 'dart:async';

import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/features/pos/data/invoices_repository.dart';
import 'package:barbershop_app/features/pos/data/pos_repository.dart';
import 'package:barbershop_app/features/pos/domain/invoice.dart';
import 'package:barbershop_app/features/pos/domain/pos_models.dart';
import 'package:barbershop_app/features/pos/presentation/invoice_detail_page.dart';
import 'package:barbershop_app/features/pos/presentation/invoice_form_page.dart';
import 'package:barbershop_app/features/pos/presentation/invoice_pdf.dart';
import 'package:barbershop_app/features/pos/presentation/invoices_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/appointment_fixtures.dart';
import '../../helpers/auth_fixtures.dart';
import '../../helpers/calendar_fixtures.dart';
import '../../helpers/home_fixtures.dart';
import '../../helpers/invoice_fixtures.dart';
import '../../helpers/load_fonts.dart';
import '../../helpers/pos_fixtures.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

Future<({FakeInvoicesRepo inv, FakePosRepo pos})> _open(
  WidgetTester tester, {
  required String start,
  bool guest = false,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final inv = FakeInvoicesRepo(guest: guest);
  final pos = FakePosRepo();
  final boot = adminBootstrapWith(const [
    'Pos_invoice-Add',
    'Pos_invoice-Edit',
    'Pos_invoice-Show_All',
  ]);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(path: '/invoices', builder: (_, _) => const InvoicesPage()),
      GoRoute(
        path: '/app/invoice/:id',
        builder: (_, s) =>
            InvoiceDetailPage(invoiceId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/app/invoice/edit/:id',
        builder: (_, s) =>
            InvoiceFormPage(invoiceId: int.parse(s.pathParameters['id']!)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(boot),
        currentUserProvider.overrideWithValue(boot.user),
        invoicesRepositoryProvider.overrideWithValue(inv),
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
  unawaited(router.push(start));
  await _settle(tester);
  return (inv: inv, pos: pos);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  group('Invoices list', () {
    testWidgets('lists invoices: number, customer, date, amount, Paid', (
      tester,
    ) async {
      await _open(tester, start: '/invoices');
      expect(find.text('Invoices'), findsOneWidget);
      expect(
        find.text('View, edit, and send customer invoices'),
        findsOneWidget,
      );
      expect(find.text('Sam Patel'), findsOneWidget);
      expect(find.text('GEN-2610-0005'), findsOneWidget);
      expect(find.text(r'$83.50'), findsNWidgets(2));
      expect(find.text('Paid'), findsNWidgets(2));
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    });

    testWidgets('search asks the server', (tester) async {
      final r = await _open(tester, start: '/invoices');
      await tester.enterText(find.byType(TextField).first, 'daniel');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(r.inv.calls, contains('list:daniel'));
      expect(find.text('Sam Patel'), findsNothing);
      expect(find.text('Daniel Okafor'), findsOneWidget);
    });

    testWidgets('tapping an invoice opens View Invoice', (tester) async {
      await _open(tester, start: '/invoices');
      await tester.tap(find.text('Sam Patel'));
      await _settle(tester);
      expect(find.text('View Invoice'), findsOneWidget);
    });
  });

  group('View Invoice', () {
    testWidgets('prints the web preview: services, discount, totals', (
      tester,
    ) async {
      await _open(tester, start: '/app/invoice/5');
      expect(find.text('Rosenthal Barbershop'), findsOneWidget);
      expect(find.text('Sam Patel'), findsOneWidget);
      expect(find.text('sam@example.com'), findsOneWidget);
      expect(find.text('GEN-2610-0005'), findsWidgets);
      expect(find.text("Men's cut"), findsOneWidget);
      expect(find.text('Hair oil'), findsOneWidget);
      expect(find.text('Total Services Amount'), findsOneWidget);
      expect(find.text(r'$65.00'), findsOneWidget);
      expect(find.text('Service Discount (10%)'), findsOneWidget);
      expect(find.text(r'-$6.50'), findsOneWidget);
      expect(find.text('Total Services Payable'), findsOneWidget);
      expect(find.text('Total Product Amount'), findsOneWidget);
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text('Tax'), findsOneWidget);
      expect(find.text('Tip'), findsOneWidget);
      expect(find.text('Total Amount'), findsOneWidget);
      expect(find.text(r'$83.50'), findsOneWidget);
    });

    testWidgets('Send Invoice Mail asks, then mails the customer', (
      tester,
    ) async {
      final r = await _open(tester, start: '/app/invoice/5');
      await tester.tap(find.widgetWithText(AppButton, 'Send Invoice Mail'));
      await _settle(tester);
      expect(
        find.text('Send this invoice to sam@example.com?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Send'));
      await _settle(tester);
      expect(r.inv.calls, contains('mail:5:-'));
      expect(find.text('Mail Successfully Send'), findsOneWidget);
    });

    testWidgets('a guest has no address: it is asked for, and checked', (
      tester,
    ) async {
      final r = await _open(tester, start: '/app/invoice/5', guest: true);
      // The guest placeholder is not printed as a contact.
      expect(find.text('info@bluecrownbarbers.com'), findsNothing);
      await tester.tap(find.widgetWithText(AppButton, 'Send Invoice Mail'));
      await _settle(tester);
      expect(find.textContaining('has no email address'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Email'),
        'nope',
      );
      await tester.tap(
        find.widgetWithText(AppButton, 'Send Invoice Mail').last,
      );
      await _settle(tester);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(r.inv.calls.where((c) => c.startsWith('mail')), isEmpty);

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Email'),
        'ravi@example.com',
      );
      await tester.tap(
        find.widgetWithText(AppButton, 'Send Invoice Mail').last,
      );
      await _settle(tester);
      expect(r.inv.calls, contains('mail:5:ravi@example.com'));
    });

    testWidgets('shows Download PDF, Print and (by permission) Edit', (
      tester,
    ) async {
      await _open(tester, start: '/app/invoice/5');
      expect(find.widgetWithText(AppButton, 'Download PDF'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Print'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Edit'), findsOneWidget);
    });

    test('the PDF is a real document with the invoice number', () async {
      final detail = InvoiceDetail.fromJson(invoiceJson(5));
      final bytes = await buildInvoicePdf(
        detail,
        const ShopInfo(
          name: 'Rosenthal Barbershop',
          email: 'info@rosenthal.test',
          phone: '+1 780 555 0100',
        ),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1500));
      expect(invoiceFileName(detail), 'Invoice-GEN-2610-0005.pdf');
    });
  });

  group('Edit Invoice', () {
    testWidgets('opens with the saved invoice and says Update', (tester) async {
      await _open(tester, start: '/app/invoice/edit/5');
      expect(find.text('Edit Invoice'), findsOneWidget);
      expect(find.text('Invoice No GEN-2610-0005'), findsOneWidget);
      expect(find.text("Men's cut"), findsWidgets);
      expect(find.text('Hair oil'), findsWidgets);
      expect(find.text('Sam Patel'), findsWidgets);
      expect(find.widgetWithText(AppButton, 'Update'), findsOneWidget);
    });

    testWidgets('Update sends the edited cart to the invoice', (tester) async {
      final r = await _open(tester, start: '/app/invoice/edit/5');
      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await _settle(tester);
      expect(r.pos.calls, contains('update:5'));
      final d = r.pos.drafts.single;
      expect(d.lines.length, 3);
      expect(d.serviceDiscount, 10);
      expect(d.tip, const Money(500));
      expect(d.lines.every((l) => l.staffId == 42), isTrue);
      expect(find.text('Edit Invoice'), findsNothing);
    });

    test('the same item done by two barbers stays two rows', () {
      final j = invoiceJson(5);
      j['cart'] = [
        {'type': 'service', 'id': 25, 'staff_id': 42, 'qty': 1},
        {'type': 'service', 'id': 25, 'staff_id': 49, 'qty': 1},
      ];
      final detail = InvoiceDetail.fromJson(j);
      final keys = {
        for (final c in detail.cart) '${c.type.name}:${c.id}:${c.staffId}': c,
      };
      expect(keys.length, 2);
      expect(
        const InvoiceLine(
          type: LineType.service,
          id: 25,
          name: 'x',
          price: Money.zero,
          qty: 1,
          uid: 'service:25:49',
        ).key,
        'service:25:49',
      );
    });
  });
}
