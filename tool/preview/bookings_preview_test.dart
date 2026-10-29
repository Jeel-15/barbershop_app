import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/appointments/presentation/appointments_page.dart';
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
    String name, {
    required bool dark,
    Future<void> Function(WidgetTester)? act,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
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
            home: const AppointmentsPage(),
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
      await act(tester);
      await settle();
    }
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

  testWidgets('list light', (t) => shot(t, 'bookings_light', dark: false));
  testWidgets(
    'search open',
    (t) => shot(
      t,
      'search_light',
      dark: false,
      act: (t) async {
        await t.tap(find.byIcon(Icons.search_rounded));
      },
    ),
  );
  testWidgets(
    'filter light',
    (t) => shot(
      t,
      'filter_light',
      dark: false,
      act: (t) async {
        await t.tap(find.byIcon(Icons.tune_rounded));
      },
    ),
  );
  testWidgets(
    'sheet dark',
    (t) => shot(
      t,
      'sheet_dark',
      dark: true,
      act: (t) async {
        await t.tap(find.text('Luke Tremblay'));
      },
    ),
  );
  testWidgets(
    'sheet light',
    (t) => shot(
      t,
      'sheet_light',
      dark: false,
      act: (t) async {
        await t.tap(find.text('Luke Tremblay'));
      },
    ),
  );
  testWidgets(
    'reschedule',
    (t) => shot(
      t,
      'reschedule_dark',
      dark: true,
      act: (t) async {
        await t.tap(find.text('Ahmed Khan'));
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.tap(find.widgetWithText(AppButton, 'Reschedule'));
      },
    ),
  );
}
