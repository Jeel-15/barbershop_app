import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/auth_fixtures.dart';
import '../../test/helpers/calendar_fixtures.dart';
import '../../test/helpers/home_fixtures.dart';
import '../../test/helpers/load_fonts.dart';

/// The whole Home page on a phone, tall enough to see all of it, so its length
/// can be judged. PREVIEW_DIR=... flutter test tool/preview/home_page_preview_test.dart
void main() {
  setUpAll(() async {
    await loadAppFonts();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.view(
            File(
              'J:/all_folder_of_C_drive/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
            ).readAsBytesSync().buffer,
          ),
        ),
      );
    await icons.load();
    ShopTime.init();
    // 10:40 in Edmonton, like the calendar fixtures.
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  for (final dark in [true, false]) {
    testWidgets('home page ${dark ? 'dark' : 'light'}', (tester) async {
      tester.view.physicalSize = const Size(390, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final today = ShopTime.ymd(ShopTime.today());
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(adminBootstrap().user),
            homeProvider.overrideWith(
              () => FixedHome(adminHomeRaw(today: today)),
            ),
            calendarProvider.overrideWith(
              () => FixedCalendar(calendarWindow(today)),
            ),
            dayAvailabilityProvider.overrideWith(
              (ref, date) async => const DayAvailability(
                openMin: 9 * 60,
                closeMin: 20 * 60,
                shopDayOff: false,
                staff: {
                  42: StaffDay(isDayOff: false, hours: [(9 * 60, 18 * 60)]),
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
              home: const HomePage(),
            ),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      while (tester.takeException() != null) {}
      await tester.runAsync(() async {
        final b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${Platform.environment['PREVIEW_DIR']}/home_page_${dark ? 'dark' : 'light'}.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
      });
    });
  }
}
