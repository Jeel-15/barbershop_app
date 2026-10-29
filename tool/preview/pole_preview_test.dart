import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/load_fonts.dart';

Future<void> shot(
  WidgetTester tester,
  String name,
  Widget child, {
  Size size = const Size(420, 260),
  bool dark = false,
  double ratio = 3,
}) async {
  tester.view.physicalSize = size * ratio;
  tester.view.devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  // Images decode outside the fake clock: give them real time.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 600)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File(
      '${Platform.environment['PREVIEW_DIR']}/$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
  });
}

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

  faces();
  for (final dark in [false, true]) {
    final d = dark ? 'dark' : 'light';
    testWidgets('pole object $d', (tester) async {
      await shot(
        tester,
        'pole_object_$d',
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BarberPole(width: 60, height: 190, phase: 0),
            SizedBox(width: 24),
            BarberPole(
              width: 60,
              height: 190,
              phase: 0.37,
              glow: 1,
              shine: 0.5,
            ),
            SizedBox(width: 40),
            BarberPole(width: 18, height: 52, phase: 0),
            SizedBox(width: 16),
            BarberPole(width: 18, height: 52, phase: 0.5, glow: 0.8),
            SizedBox(width: 16),
            BarberPole(width: 24, height: 64, phase: 0.25, shine: 0.5),
          ],
        ),
        size: const Size(520, 240),
        dark: dark,
        ratio: 3,
      );
    });
  }
}

/// Every state of the refresh indicator, side by side, at phone size.
void faces() {
  Widget cell(String caption, Widget face) => SizedBox(
    width: 168,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(caption, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        face,
      ],
    ),
  );
  for (final dark in [false, true]) {
    final d = dark ? 'dark' : 'light';
    testWidgets('pole faces $d', (tester) async {
      await shot(
        tester,
        'pole_faces_$d',
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            cell(
              'pull 0.2',
              const PoleRefreshFace(
                value: 0.2,
                mode: PoleMode.pulling,
                phase: 0.3,
                label: 'Pull to refresh',
              ),
            ),
            cell(
              'pull 0.45',
              const PoleRefreshFace(
                value: 0.45,
                mode: PoleMode.pulling,
                phase: 0.7,
                label: 'Pull to refresh',
              ),
            ),
            cell(
              'pull 0.75',
              const PoleRefreshFace(
                value: 0.75,
                mode: PoleMode.pulling,
                phase: 1.1,
                label: 'Pull to refresh',
                sublabel: 'Updated 2:41 PM',
              ),
            ),
            cell(
              'armed 1.0 (pop, ring)',
              const PoleRefreshFace(
                value: 1.0,
                mode: PoleMode.armed,
                phase: 1.5,
                pop: 0.35,
                ring: 0.3,
                label: 'Release to refresh',
              ),
            ),
            cell(
              'armed 1.4 stretched',
              const PoleRefreshFace(
                value: 1.4,
                mode: PoleMode.armed,
                phase: 2.0,
                pop: 1,
                ring: 1,
                label: 'Release to refresh',
              ),
            ),
            cell(
              'loading a',
              const PoleRefreshFace(
                value: 1,
                mode: PoleMode.loading,
                phase: 3.0,
                label: 'Refreshing…',
              ),
            ),
            cell(
              'loading b',
              const PoleRefreshFace(
                value: 1,
                mode: PoleMode.loading,
                phase: 3.35,
                label: 'Refreshing…',
              ),
            ),
            cell(
              'success + glint',
              const PoleRefreshFace(
                value: 1,
                mode: PoleMode.success,
                phase: 4.2,
                shine: 0.5,
                label: 'Updated 2:41 PM',
              ),
            ),
            cell(
              'failure',
              const PoleRefreshFace(
                value: 1,
                mode: PoleMode.failure,
                phase: 4.2,
                label: "Couldn't refresh",
                sublabel: 'Showing what you had',
              ),
            ),
          ],
        ),
        size: const Size(520, 330),
        dark: dark,
        ratio: 2,
      );
    });
  }
}
