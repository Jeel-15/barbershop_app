import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/presentation/calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/auth_fixtures.dart';
import '../../test/helpers/calendar_fixtures.dart';
import '../../test/helpers/load_fonts.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    // A fixed "now" (10:40 in Edmonton) so the picture does not depend on the clock.
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  Future<void> shot(
    WidgetTester tester,
    String name, {
    required bool dark,
    Future<void> Function()? act,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final day = ShopTime.ymd(ShopTime.today());
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(adminBootstrap().user),
          calendarProvider.overrideWith(
            () => FixedCalendar(calendarWindow(day)),
          ),
          dayAvailabilityProvider.overrideWith(
            (ref, date) async => const DayAvailability(
              openMin: 9 * 60,
              closeMin: 20 * 60,
              shopDayOff: false,
              staff: {
                42: StaffDay(
                  isDayOff: false,
                  hours: [(9 * 60, 13 * 60), (14 * 60, 20 * 60)],
                ),
                49: StaffDay(isDayOff: false, hours: [(9 * 60, 15 * 60)]),
              },
            ),
          ),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: const CalendarPage(),
          ),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      while (tester.takeException() != null) {}
    }

    await settle();
    if (act != null) {
      await act();
      await settle();
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      final b =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${Platform.environment['PREVIEW_DIR']}/$name.png',
      ).writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  for (final dark in [true, false]) {
    testWidgets(
      'calendar ${dark ? 'dark' : 'light'}',
      (t) => shot(t, 'calendar_${dark ? 'dark' : 'light'}', dark: dark),
    );
  }
  testWidgets(
    'calendar free spot marked',
    (t) => shot(
      t,
      'calendar_mark_dark',
      dark: true,
      act: () async {
        // an empty free spot of Mike's column, around 11:45
        await t.tapAt(const Offset(110, 470));
      },
    ),
  );
}
