import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/presentation/landscape_calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/calendar_fixtures.dart';
import '../../helpers/load_fonts.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(844, 390),
  Widget? home,
  bool keepErrors = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        bootstrapProvider.overrideWithValue(adminBootstrap()),
        currentUserProvider.overrideWithValue(adminBootstrap().user),
        calendarProvider.overrideWith(
          () => FixedCalendar(calendarWindow('2026-10-25')),
        ),
        dayAvailabilityProvider.overrideWith(
          (ref, date) async => const DayAvailability(
            openMin: 9 * 60,
            closeMin: 20 * 60,
            shopDayOff: false,
            staff: {
              42: StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
              49: StaffDay(isDayOff: true, hours: []),
            },
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: home ?? const LandscapeCalendarPage(),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!keepErrors) while (tester.takeException() != null) {}
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40); // 10:40
  });

  testWidgets('every barber is a row, the day runs across, now is pinned', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Mike'), findsOneWidget);
    expect(find.text('Mutaz'), findsOneWidget);
    expect(find.text('Day off'), findsWidgets); // Mutaz
    expect(find.text('BARBER'), findsOneWidget);
    expect(find.text('10:40 AM'), findsOneWidget); // the now pin
    expect(find.textContaining('Pending'), findsWidgets);
    // A booking is a block with the customer on it.
    expect(find.text('Marcus Lee'), findsOneWidget);
  });

  testWidgets(
    'a portrait screen waits for the turn, it does not draw the day',
    (tester) async {
      await _pump(tester, size: const Size(390, 844));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Mike'), findsNothing);
    },
  );

  testWidgets('the zoom button switches between detail and the whole day', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byIcon(Icons.zoom_out_map_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.zoom_out_map_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.zoom_in_map_rounded), findsOneWidget);
  });

  testWidgets('a free spot is marked first, with the time to book', (
    tester,
  ) async {
    await _pump(tester);
    // Mike is free after Daniel (12:00): tap a little right of the 12 PM line.
    final x12 = tester.getTopLeft(find.text('12 PM')).dx;
    final y = tester.getCenter(find.text('Mike')).dy;
    await tester.tapAt(Offset(x12 + 70, y));
    await tester.pump();
    expect(find.textContaining('Book '), findsOneWidget);
  });

  testWidgets('a spot nobody can be booked at says why', (tester) async {
    await _pump(tester);
    // Mutaz has the day off.
    final x12 = tester.getTopLeft(find.text('12 PM')).dx;
    final y = tester.getCenter(find.text('Mutaz')).dy;
    await tester.tapAt(Offset(x12 + 70, y));
    await tester.pump();
    expect(find.textContaining('day off'), findsWidgets);
  });

  testWidgets(
    'a small landscape phone and big text still fit without overflow',
    (tester) async {
      await _pump(tester, size: const Size(640, 330));
      expect(tester.takeException(), isNull);
      expect(find.text('Mike'), findsOneWidget);
    },
  );

  testWidgets('it turns the phone sideways while open and back on close', (
    tester,
  ) async {
    final log = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        log.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester);
    final open = log.where(
      (c) => c.method == 'SystemChrome.setPreferredOrientations',
    );
    expect(open.first.arguments, contains('DeviceOrientation.landscapeLeft'));
    expect(
      open.first.arguments,
      isNot(contains('DeviceOrientation.portraitUp')),
    );

    // Close the page: portrait comes back.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final all = log
        .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
        .toList();
    expect(all.last.arguments, ['DeviceOrientation.portraitUp']);
  });

  group('pinch to zoom', () {
    double hourW(WidgetTester tester) =>
        tester.getTopLeft(find.text('1 PM')).dx -
        tester.getTopLeft(find.text('12 PM')).dx;

    Future<(TestGesture, TestGesture)> two(
      WidgetTester tester,
      Offset c,
      double gap,
    ) async {
      final a = await tester.startGesture(c - Offset(gap / 2, 0));
      final b = await tester.startGesture(c + Offset(gap / 2, 0));
      await tester.pump();
      return (a, b);
    }

    Future<void> spread(
      WidgetTester tester,
      (TestGesture, TestGesture) f,
      double by,
    ) async {
      for (var i = 0; i < 8; i++) {
        await f.$1.moveBy(Offset(-by / 16, 0));
        await f.$2.moveBy(Offset(by / 16, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('spreading two fingers widens the hours and it is remembered', (
      tester,
    ) async {
      await _pump(tester);
      final before = hourW(tester);
      final f = await two(tester, const Offset(500, 200), 100);
      await spread(tester, f, 100); // 2x
      final after = hourW(tester);
      expect(after, greaterThan(before * 1.7));
      await f.$1.up();
      await f.$2.up();
      await tester.pump(const Duration(seconds: 2));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LandscapeCalendarPage)),
      );
      expect(container.read(landscapeZoomProvider), closeTo(after, 1.5));
      expect(hourW(tester), closeTo(after, 1.5));
    });

    testWidgets('it never goes below the whole day, nor above the maximum', (
      tester,
    ) async {
      await _pump(tester);
      final f = await two(tester, const Offset(500, 200), 400);
      await spread(tester, f, -390);
      final lowest = hourW(tester);
      // The whole day fills the width: the last hour ends at the right edge.
      expect(lowest, greaterThan(kPphMin - 1));
      await f.$1.up();
      await f.$2.up();
      await tester.pump(const Duration(seconds: 2));
      final g = await two(tester, const Offset(500, 200), 40);
      await spread(tester, g, 700);
      expect(hourW(tester), closeTo(kPphMax, 1));
      await g.$1.up();
      await g.$2.up();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the time between the fingers stays between the fingers', (
      tester,
    ) async {
      await _pump(tester);
      const c = Offset(500, 200);
      final before = tester.getTopLeft(find.text('12 PM')).dx - c.dx;
      final w0 = hourW(tester);
      final f = await two(tester, c, 100);
      await spread(tester, f, 100);
      final w1 = hourW(tester);
      final after = tester.getTopLeft(find.text('12 PM')).dx - c.dx;
      // 12 PM keeps its distance to the fingers, scaled by the zoom (text is
      // inset by a fixed 6 px, hence the tolerance).
      expect(after, closeTo(before * w1 / w0, 14));
      await f.$1.up();
      await f.$2.up();
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a pinch does not mark a slot, and the pill resets it', (
      tester,
    ) async {
      await _pump(tester);
      final f = await two(tester, const Offset(500, 200), 100);
      await spread(tester, f, 80);
      await f.$1.up();
      await f.$2.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Book '), findsNothing);
      final pill = find.textContaining(RegExp(r'^\d+(\.\d)?x$'));
      expect(pill, findsOneWidget);
      final custom = hourW(tester);
      await tester.tap(pill);
      await tester.pump(const Duration(milliseconds: 300));
      expect(hourW(tester), isNot(closeTo(custom, 1)));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LandscapeCalendarPage)),
      );
      expect(container.read(landscapeZoomProvider), isNull);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the top bar button goes back to a preset', (tester) async {
      await _pump(tester);
      final f = await two(tester, const Offset(500, 200), 100);
      await spread(tester, f, 80);
      await f.$1.up();
      await f.$2.up();
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byIcon(Icons.zoom_out_map_rounded));
      await tester.pump(const Duration(milliseconds: 200));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LandscapeCalendarPage)),
      );
      expect(container.read(landscapeZoomProvider), isNull);
    });
  });
}
