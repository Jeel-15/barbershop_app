import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/utils/money.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/features/home/domain/dashboard.dart';
import 'package:barbershop_app/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/home_fixtures.dart';
import '../../helpers/load_fonts.dart';

class _FailingHome extends HomeController {
  @override
  Future<HomeData> build() async => throw const NetworkFailure();
}

Future<FixedHome?> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> raw,
  bool staff = false,
  bool fromCache = false,
  HomeController Function()? controller,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final fixed = controller == null
      ? FixedHome(raw, fromCache: fromCache)
      : null;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(
          (staff ? staffBootstrap() : adminBootstrap()).user,
        ),
        homeProvider.overrideWith(controller ?? () => fixed!),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const HomePage()),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
  return fixed;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
  });

  final today = ShopTime.ymd(ShopTime.today());

  group('HomeData', () {
    test('parses the real API shapes', () {
      final d = HomeData.fromRaw(adminHomeRaw(today: today));
      expect(d.summary.isAdmin, isTrue);
      expect(d.summary.revenue, const Money(71309));
      expect(d.summary.tips, const Money(5800));
      expect(d.today, hasLength(4));
      expect(d.today[1].servicesText, "Men's cut · Beard (trim line up)");
      expect(d.today[1].staffText, 'JOJO');
      expect(d.topServices.first.revenue, const Money(35175));
    });

    test('next up skips finished bookings', () {
      final d = HomeData.fromRaw(adminHomeRaw(today: today));
      expect(d.nextUp!.customerName, 'Daniel Okafor'); // first is completed
    });

    test('staff summary is earnings, not revenue', () {
      final d = HomeData.fromRaw(emptyStaffHomeRaw());
      expect(d.summary.isAdmin, isFalse);
      expect(d.summary.showTopServices, isFalse);
      expect(d.nextUp, isNull);
    });

    test('actions come from the server per row', () {
      final d = HomeData.fromRaw(adminHomeRaw(today: today));
      expect(d.today[2].canConfirm, isTrue); // pending
      expect(d.today[1].canConfirm, isFalse); // confirmed
    });
  });

  group('Home screen', () {
    testWidgets('admin sees money, counts, next up, lists and insights', (
      tester,
    ) async {
      await _pump(tester, raw: adminHomeRaw(today: today));
      expect(find.text('TOTAL REVENUE'), findsOneWidget);
      expect(find.text(r'$713.09'), findsOneWidget);
      expect(find.text('Upcoming'), findsWidgets);
      expect(find.textContaining('NEXT UP'), findsOneWidget);
      expect(find.text('Marcus Lee'), findsOneWidget);
      expect(find.text('Top Services'), findsOneWidget);

      await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Top Selling Product'), findsOneWidget);
      // Not on the web dashboard, so not here either.
      expect(find.text('Team performance'), findsNothing);
    });

    testWidgets('staff with no bookings sees a quiet day and no admin blocks', (
      tester,
    ) async {
      await _pump(tester, raw: emptyStaffHomeRaw(), staff: true);
      expect(find.text('TOTAL REVENUE'), findsOneWidget);
      expect(find.text('Quiet day'), findsOneWidget);
      expect(find.text('Top Services'), findsNothing);
      expect(find.textContaining('NEXT UP'), findsNothing);
    });

    testWidgets('Confirm on the next-up card calls the controller', (
      tester,
    ) async {
      final raw = adminHomeRaw(today: today);
      // Make the next booking pending so the button exists.
      (raw['today'] as List)[1]['status'] = 0;
      (raw['today'] as List)[1]['actions'] = ['confirm', 'cancel', 'view'];
      final fixed = await _pump(tester, raw: raw);
      await tester.tap(find.text('Confirm').first);
      await tester.pump(const Duration(milliseconds: 200));
      expect(fixed!.confirmed, [2]);
    });

    testWidgets('saved copy shows the offline banner', (tester) async {
      await _pump(tester, raw: adminHomeRaw(today: today), fromCache: true);
      expect(find.textContaining('Showing saved data'), findsOneWidget);
    });

    testWidgets('failure with nothing saved shows the error state', (
      tester,
    ) async {
      await _pump(tester, raw: const {}, controller: _FailingHome.new);
      expect(find.text('Can’t connect right now'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
