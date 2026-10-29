import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/application/booking_form_controller.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/presentation/booking_form_page.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/appointment_fixtures.dart';
import '../../test/helpers/auth_fixtures.dart';
import '../../test/helpers/load_fonts.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 25, 16, 40);
  });

  Future<void> shot(
    WidgetTester tester,
    String name,
    BookingTarget target, {
    required bool dark,
    double height = 1500,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bootstrapProvider.overrideWithValue(adminBootstrap()),
          currentUserProvider.overrideWithValue(adminBootstrap().user),
          appointmentsRepositoryProvider.overrideWithValue(
            FakeAppointmentsRepo(),
          ),
          customersRepositoryProvider.overrideWithValue(FakeCustomersRepo()),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: BookingFormPage(target: target),
          ),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
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
    'edit light',
    (t) => shot(
      t,
      'booking_edit_light',
      const BookingTarget(editId: 4),
      dark: false,
    ),
  );
  testWidgets(
    'new dark',
    (t) => shot(
      t,
      'booking_new_dark',
      const BookingTarget(staffId: 42, date: '2026-10-26', time: '09:30'),
      dark: true,
      height: 900,
    ),
  );
}
