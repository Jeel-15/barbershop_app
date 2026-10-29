import 'dart:async';

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/staff/data/staff_repository.dart';
import 'package:barbershop_app/features/reports/application/reports_controller.dart';
import 'package:barbershop_app/features/reports/data/reports_repository.dart';
import 'package:barbershop_app/features/reports/domain/report_models.dart';
import 'package:barbershop_app/features/reports/presentation/reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/load_fonts.dart';
import '../../helpers/staff_fixtures.dart';
import '../../helpers/reports_fixtures.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

Future<FakeReports> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 2800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeReports();
  final boot = adminBootstrap();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(path: '/app/reports', builder: (_, _) => const ReportsPage()),
      GoRoute(
        path: '/app/invoice/:id',
        builder: (_, _) => const Text('INVOICE'),
      ),
      GoRoute(path: '/app/staff/:id', builder: (_, _) => const Text('STAFF')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(boot),
        currentUserProvider.overrideWithValue(boot.user),
        reportsRepositoryProvider.overrideWithValue(repo),
        // The Staff Name filter lists the team.
        staffRepositoryProvider.overrideWithValue(FakeStaffRepo()),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await _settle(tester);
  unawaited(router.push('/app/reports'));
  await _settle(tester);
  return repo;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
  });

  testWidgets('the four headline cards and the Earning tab', (tester) async {
    await _open(tester);
    expect(find.text('Reports'), findsOneWidget);
    expect(
      find.text('Analyze revenue, appointments, staff performance, and sales'),
      findsOneWidget,
    );
    expect(find.text('Total Revenue'), findsOneWidget);
    expect(find.text(r'$1,250.00'), findsOneWidget);
    expect(find.text('Total Appointment'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Discount Amount'), findsOneWidget);
    expect(find.text('Total Tips'), findsOneWidget);
    // Earning tab
    expect(find.text('Total Earning'), findsOneWidget);
    expect(find.text(r'$510.00'), findsOneWidget);
    expect(find.text('Product Commission'), findsOneWidget);
    expect(find.text('Service Commission'), findsOneWidget);
    expect(find.text('Sam Patel'), findsOneWidget);
    expect(find.text('Sub Total'), findsOneWidget);
    expect(find.text('Total Amount'), findsOneWidget);
  });

  testWidgets('Payment Methods and Staff tabs', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Payment Methods'));
    await _settle(tester);
    expect(find.text('Payment Method Analytics'), findsOneWidget);
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text(r'$800.00'), findsOneWidget);

    await tester.tap(find.text('Staff'));
    await _settle(tester);
    expect(find.text('Staff Performance'), findsOneWidget);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('Service Comm.'), findsOneWidget);
    expect(find.text('Product Comm.'), findsOneWidget);
    await tester.tap(find.text('Mike'));
    await _settle(tester);
    expect(find.text('STAFF'), findsOneWidget);
  });

  testWidgets('Invoice tab: web columns, opens the invoice', (tester) async {
    await _open(tester);
    await tester.tap(find.text('Invoice'));
    await _settle(tester);
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('GEN-2610-0005'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('Staff earned'), findsOneWidget);
    await tester.tap(find.text('GEN-2610-0005'));
    await _settle(tester);
    expect(find.text('INVOICE'), findsOneWidget);
  });

  testWidgets('Product and Top Selling Products tabs', (tester) async {
    await _open(tester);
    // The tab chips scroll sideways.
    await tester.drag(find.text('Earning'), const Offset(-500, 0));
    await tester.pump();
    await tester.tap(find.text('Product'));
    await _settle(tester);
    expect(find.text('Product Sell History'), findsOneWidget);
    expect(find.text('Hair oil'), findsOneWidget);
    expect(find.textContaining('Sell By Mike'), findsOneWidget);

    await tester.tap(find.text('Top Selling Products').first);
    await _settle(tester);
    expect(find.text('Total Product Amount'), findsOneWidget);
    expect(find.text('Total Discount Paid'), findsWidgets);
    expect(find.text('Total Commission Paid'), findsOneWidget);
    expect(find.text('Sell Unit'), findsOneWidget);
    expect(find.text(r'$140.00'), findsOneWidget);
  });

  testWidgets('Reports Filter: a staff narrows every tab', (tester) async {
    final r = await _open(tester);
    await tester.tap(find.byIcon(Icons.tune_rounded));
    await _settle(tester);
    expect(find.text('Reports Filter'), findsWidgets);
    expect(find.text('Start Date'), findsOneWidget);
    expect(find.text('Staff Name'), findsOneWidget);
    expect(find.text('All Staff'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppChoiceChip, 'Mutaz'));
    await tester.pump();
    await tester.tap(find.widgetWithText(AppButton, 'Filter'));
    await _settle(tester);
    expect(r.calls, contains('overview:-:-:49'));
    expect(r.calls, contains('earning:-:-:49'));
  });

  test('the filter keeps only what is set', () {
    const f = ReportsFilter(start: '2026-10-01', staffId: 3);
    expect(f.toQuery(), {'start_date': '2026-10-01', 'staff_id': 3});
    expect(f.activeCount, 2);
    expect(const ReportsFilter().isClear, isTrue);
    expect(f.copyWith(staffId: null).toQuery(), {'start_date': '2026-10-01'});
  });

  test('staff options provider type is reachable', () {
    expect(reportStaffOptionsProvider, isNotNull);
  });
}
