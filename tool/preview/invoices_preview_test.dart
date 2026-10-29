import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/appointments/data/appointments_repository.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:barbershop_app/features/pos/data/pos_repository.dart';
import 'package:barbershop_app/features/pos/data/invoices_repository.dart';
import 'package:barbershop_app/features/pos/presentation/invoice_detail_page.dart';
import 'package:barbershop_app/features/pos/presentation/invoices_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/appointment_fixtures.dart';
import '../../test/helpers/auth_fixtures.dart';
import '../../test/helpers/load_fonts.dart';
import '../../test/helpers/invoice_fixtures.dart';
import '../../test/helpers/pos_fixtures.dart';

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
    Future<void> Function(WidgetTester)? act,
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
          posRepositoryProvider.overrideWithValue(FakePosRepo()),
          invoicesRepositoryProvider.overrideWithValue(FakeInvoicesRepo()),
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

  testWidgets(
    'invoices list',
    (t) => shot(t, 'invoices_dark', const InvoicesPage(), dark: true),
  );
  testWidgets(
    'invoice detail dark',
    (t) => shot(
      t,
      'invoice_detail_dark',
      const InvoiceDetailPage(invoiceId: 5),
      dark: true,
      height: 1250,
    ),
  );
  testWidgets(
    'invoice detail light',
    (t) => shot(
      t,
      'invoice_detail_light',
      const InvoiceDetailPage(invoiceId: 5),
      dark: false,
      height: 1250,
    ),
  );
}
