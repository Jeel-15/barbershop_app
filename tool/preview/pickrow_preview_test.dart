import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/load_fonts.dart';

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
  });

  for (final dark in [false, true]) {
    testWidgets('pick rows ${dark ? 'dark' : 'light'}', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 430 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    PickRow(
                      name: 'Skin fade',
                      detail: r'$35.00 · 30 min',
                      count: 0,
                      onTap: () {},
                    ),
                    PickRow(
                      name: 'Men\u2019s cut',
                      detail: r'$30.00 · 30 min',
                      count: 1,
                      onTap: () {},
                    ),
                    PickRow(
                      name: 'Beard (razor lineup)',
                      detail: r'$25.00 · 20 min',
                      count: 2,
                      onTap: () {},
                    ),
                    PickRow(
                      name: 'Hair oil',
                      detail: r'$20.00 · 10 in stock',
                      count: 0,
                      placeholder: Icons.shopping_bag_outlined,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        final b =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 1);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${Platform.environment['PREVIEW_DIR']}/pickrow_${dark ? 'dark' : 'light'}.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
      });
    });
  }
}
