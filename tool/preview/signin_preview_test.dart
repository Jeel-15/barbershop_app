import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/presentation/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/auth_fixtures.dart';
import '../../test/helpers/load_fonts.dart';

void main() {
  setUpAll(loadAppFonts);
  for (final dark in [true, false]) {
    testWidgets('signin ${dark ? "dark" : "light"}', (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = await AuthHarness.create(
        prefs: {'last_email': 'apitest.admin@rosen.test'},
      );
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? AppTheme.dark : AppTheme.light,
              home: const SignInScreen(),
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      while (tester.takeException() != null) {}
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 800)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() async {
        final b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${Platform.environment['PREVIEW_DIR']}/signin_${dark ? "dark" : "light"}.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
      });
    });
  }
}
