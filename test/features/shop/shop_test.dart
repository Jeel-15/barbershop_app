import 'dart:async';

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/shop/data/shop_repository.dart';
import 'package:barbershop_app/features/shop/domain/shop_models.dart';
import 'package:barbershop_app/features/shop/presentation/closures_page.dart';
import 'package:barbershop_app/features/shop/presentation/settings_page.dart';
import 'package:barbershop_app/features/shop/presentation/slots_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/load_fonts.dart';
import '../../helpers/shop_fixtures.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
}

const _closure = [
  'Shop_Closures-Add',
  'Shop_Closures-Edit',
  'Shop_Closures-Delete',
];

Future<FakeShop> _open(
  WidgetTester tester,
  Widget page, {
  List<String> perms = _closure,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = FakeShop();
  final boot = adminBootstrapWith(perms);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Text('BACK')),
      GoRoute(path: '/page', builder: (_, _) => page),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(boot),
        currentUserProvider.overrideWithValue(boot.user),
        shopRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await _settle(tester);
  unawaited(router.push('/page'));
  await _settle(tester);
  return repo;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
  });

  group('Slot Configuration', () {
    testWidgets('a card per day with Open / Close Time and Day Off', (
      tester,
    ) async {
      await _open(tester, const SlotsPage());
      expect(find.text('Slot Configuration'), findsOneWidget);
      expect(
        find.text('Configure business hours and appointment slots'),
        findsOneWidget,
      );
      expect(find.text('Monday'), findsOneWidget);
      expect(find.text('9:00 AM'), findsOneWidget);
      expect(find.text('8:00 PM'), findsOneWidget);
      expect(find.text('Shop Open Time'), findsNWidgets(2));
      expect(find.text('Day Off'), findsNWidgets(3));
    });

    testWidgets('an open day without times is refused, in words', (
      tester,
    ) async {
      final r = await _open(tester, const SlotsPage());
      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await _settle(tester);
      expect(
        find.text('Opening and closing time are required for an open day.'),
        findsOneWidget,
      );
      expect(r.savedHours, isNull);
    });

    testWidgets('a day off needs no times; breaks are sent back unchanged', (
      tester,
    ) async {
      final r = await _open(tester, const SlotsPage());
      // Wednesday (open, no times) -> Day Off
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await _settle(tester);
      final sent = r.savedHours!;
      expect(sent.length, 3);
      expect(sent.last.isDayOff, isTrue);
      expect(sent.first.toJson()['open_time'], '09:00');
      expect(sent.first.toJson()['breaks'], [
        {'break_start': '13:00', 'break_end': '14:00'},
      ]);
      expect(
        find.text('Slot configuration stored successfully.'),
        findsOneWidget,
      );
    });
  });

  group('Settings', () {
    testWidgets('General: the web fields and Update', (tester) async {
      final r = await _open(tester, const SettingsPage());
      expect(find.text('Settings'), findsOneWidget);
      expect(
        find.text('Manage business settings, payments, and account security'),
        findsOneWidget,
      );
      expect(find.text('General Business Settings'), findsOneWidget);
      expect(find.text('Service Reminder Day'), findsOneWidget);
      expect(find.text('Service Default Duration (Minutes)'), findsOneWidget);
      expect(find.text('Service Fee'), findsOneWidget);
      expect(find.text('Invoice Mail Send'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Service Reminder Day'),
        '10',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await _settle(tester);
      expect(r.calls, contains('general:10:30:1.50:true'));
    });

    testWidgets('General: whole numbers only', (tester) async {
      final r = await _open(tester, const SettingsPage());
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Service Reminder Day'),
        '0',
      );
      await tester.tap(find.widgetWithText(AppButton, 'Update'));
      await _settle(tester);
      expect(find.text('Enter a whole number, 1 or more'), findsOneWidget);
      expect(r.calls.where((c) => c.startsWith('general')), isEmpty);
    });

    testWidgets('Contact: required fields and the web labels', (tester) async {
      final r = await _open(tester, const SettingsPage());
      await tester.tap(find.text('Contact Details'));
      await _settle(tester);
      expect(find.text('Footer About Text'), findsOneWidget);
      expect(find.text('Address *'), findsOneWidget);
      expect(find.text('Info Email *'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(AppTextField, 'Address *'),
        '',
      );
      await tester.tap(
        find.widgetWithText(AppButton, 'Update Contact Details'),
      );
      await _settle(tester);
      expect(
        find.text('The contact address field is required.'),
        findsOneWidget,
      );
      expect(r.savedContact, isNull);

      await tester.enterText(
        find.widgetWithText(AppTextField, 'Address *'),
        '2 Side St',
      );
      await tester.tap(
        find.widgetWithText(AppButton, 'Update Contact Details'),
      );
      await _settle(tester);
      expect(r.savedContact!['contact_address'], '2 Side St');
      expect(r.savedContact!['contact_email'], 'info@rosen.test');
    });

    testWidgets('Payment Options tab leads to the payment methods', (
      tester,
    ) async {
      await _open(tester, const SettingsPage());
      await tester.tap(find.text('Payment Options'));
      await _settle(tester);
      expect(find.text('Custom Payment Methods'), findsOneWidget);
    });
  });

  group('Shop Closures', () {
    testWidgets('list: date, type, time and reason', (tester) async {
      await _open(tester, const ClosuresPage());
      expect(find.text('Shop Closures'), findsOneWidget);
      expect(
        find.text('Schedule full-day or partial shop closures'),
        findsOneWidget,
      );
      expect(find.text('25 Dec 2026'), findsOneWidget);
      expect(find.text('Full Day Close'), findsOneWidget);
      expect(find.text('Full Day'), findsOneWidget);
      expect(find.text('Partial Day'), findsOneWidget);
      expect(find.text('09:00 AM - 11:00 AM'), findsOneWidget);
      expect(find.text('Christmas'), findsOneWidget);
    });

    testWidgets('search by reason, delete in the web words', (tester) async {
      final r = await _open(tester, const ClosuresPage());
      await tester.enterText(find.byType(TextField).first, 'plumb');
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);
      expect(r.calls, contains('closures:plumb'));
      expect(find.text('Christmas'), findsNothing);
      await tester.tap(find.byTooltip('More'));
      await _settle(tester);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(
        find.text('Are you sure to delete Shop Closures?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Yes, confirm!'));
      await _settle(tester);
      expect(r.calls, contains('delete:2'));
    });

    testWidgets('Add Closures: the web messages', (tester) async {
      final r = await _open(tester, const ClosuresPage());
      await tester.tap(find.byIcon(Icons.add_rounded));
      await _settle(tester);
      expect(find.text('Add Closures'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(find.text('Please select the closure date'), findsOneWidget);
      expect(find.text('Please enter the reason for closure'), findsOneWidget);

      // Not a full day: start and end are needed.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, 'Save'));
      await _settle(tester);
      expect(
        find.text('Start time is required if not a full day closure'),
        findsOneWidget,
      );
      expect(
        find.text('End time is required if not a full day closure'),
        findsOneWidget,
      );
      expect(r.calls.where((c) => c.startsWith('create')), isEmpty);
    });

    testWidgets('no rights: no Add and no menu', (tester) async {
      await _open(tester, const ClosuresPage(), perms: const []);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byTooltip('More'), findsNothing);
    });

    test('a closure sends no times for a full day', () {
      const full = ClosureInput(
        date: '2026-12-25',
        fullDay: true,
        start: '09:00',
        end: '10:00',
        reason: ' x ',
      );
      expect(full.toJson().containsKey('start_time'), isFalse);
      expect(full.toJson()['reason'], 'x');
      const part = ClosureInput(
        date: '2026-12-25',
        fullDay: false,
        start: '09:00',
        end: '10:00',
        reason: 'y',
      );
      expect(part.toJson()['start_time'], '09:00');
    });

    test('ValidationFailure shape used by the forms', () {
      const f = ValidationFailure(
        'bad',
        fieldErrors: {
          'end_time': [
            'End time must be after start time for a partial-day closure.',
          ],
        },
      );
      expect(f.errorFor('end_time'), contains('after start time'));
    });
  });
}
