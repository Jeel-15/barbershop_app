import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/me/data/me_repository.dart';
import 'package:barbershop_app/features/me/presentation/profile_page.dart';
import 'package:barbershop_app/features/me/presentation/staff_report_page.dart';
import 'package:barbershop_app/features/me/presentation/working_hours_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/auth_fixtures.dart';
import '../../test/helpers/load_fonts.dart';
import '../../test/helpers/me_fixtures.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget page, {
    required bool dark,
    double height = 844,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWithValue(staffBootstrap()),
          currentUserProvider.overrideWithValue(staffBootstrap().user),
          meRepositoryProvider.overrideWithValue(FakeMe()),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: page,
          ),
        ),
      ),
    );
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    while (tester.takeException() != null) {}
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
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

  testWidgets(
    'hours',
    (t) => shot(
      t,
      'hours_dark',
      const WorkingHoursPage(),
      dark: true,
      height: 1000,
    ),
  );
  testWidgets(
    'report',
    (t) => shot(
      t,
      'report_dark',
      const StaffReportPage(),
      dark: true,
      height: 1000,
    ),
  );
  testWidgets(
    'profile',
    (t) =>
        shot(t, 'profile_dark', const ProfilePage(), dark: true, height: 1500),
  );
}
