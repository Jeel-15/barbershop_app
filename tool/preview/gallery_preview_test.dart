// Temporary helper: renders the design gallery to PNG so it can be inspected.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/dev/gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/helpers/load_fonts.dart';

const outDir = String.fromEnvironment(
  'PREVIEW_DIR',
  defaultValue: 'build/preview',
);

void main() {
  setUpAll(() {
    loadAppFonts();
    ShopTime.init();
  });

  for (final dark in [true, false]) {
    testWidgets('gallery ${dark ? 'dark' : 'light'}', (tester) async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({
        'theme_mode': dark ? 'dark' : 'light',
      });
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(390 * 2, 4700 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
          child: Consumer(
            builder: (context, ref, _) => RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: ref.watch(themeModeProvider),
                home: const GalleryScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(outDir).createSync(recursive: true);
        File(
          '$outDir/gallery_${dark ? 'dark' : 'light'}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
