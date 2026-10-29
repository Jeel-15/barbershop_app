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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/auth_fixtures.dart';
import '../../test/helpers/calendar_fixtures.dart';
import '../../test/helpers/home_fixtures.dart';
import '../../test/helpers/load_fonts.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  Future<void> shot(
    WidgetTester tester,
    String name, {
    required bool dark,
    required Map<String, dynamic> raw,
    required bool staff,
    double height = 2400,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final user = (staff ? staffBootstrap() : adminBootstrap()).user;
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(user),
          homeProvider.overrideWith(() => FixedHome(raw)),
          calendarProvider.overrideWith(
            () => FixedCalendar(calendarWindow(ShopTime.ymd(ShopTime.today()))),
          ),
          dayAvailabilityProvider.overrideWith(
            (ref, date) async => DayAvailability.fallback(),
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

  testWidgets('home admin dark', (tester) async {
    await shot(
      tester,
      'home_admin_dark',
      dark: true,
      staff: false,
      raw: adminHomeRaw(today: ShopTime.ymd(ShopTime.today())),
    );
  });
  testWidgets('home admin light', (tester) async {
    await shot(
      tester,
      'home_admin_light',
      dark: false,
      staff: false,
      raw: adminHomeRaw(today: ShopTime.ymd(ShopTime.today())),
    );
  });
  testWidgets('home staff empty dark', (tester) async {
    await shot(
      tester,
      'home_staff_dark',
      dark: true,
      staff: true,
      raw: emptyStaffHomeRaw(),
      height: 900,
    );
  });
}
