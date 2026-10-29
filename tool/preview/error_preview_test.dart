import 'dart:io';
import 'dart:ui' as ui;

import 'package:barbershop_app/core/errors/failure.dart';
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
  required Size size,
  bool dark = false,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 600)),
  );
  await tester.pump(const Duration(milliseconds: 700));
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

  for (final dark in [false, true]) {
    final d = dark ? 'dark' : 'light';
    testWidgets('error moods $d', (tester) async {
      Widget cell(bool online, ErrorState s) => SizedBox(
        width: 195,
        height: 330,
        child: ConnectionScope(online: online, child: s),
      );
      await shot(
        tester,
        'error_moods_$d',
        Wrap(
          children: [
            cell(
              false,
              ErrorState(
                message: const NetworkFailure().message,
                onRetry: () {},
              ),
            ),
            cell(
              true,
              ErrorState(
                message: const NetworkFailure().message,
                onRetry: () {},
              ),
            ),
            cell(
              true,
              ErrorState(
                message: const TimeoutFailure().message,
                onRetry: () {},
              ),
            ),
            cell(
              true,
              ErrorState(
                message: const ServerFailure().message,
                supportCode: 'req_8f2a',
                onRetry: () {},
              ),
            ),
          ],
        ),
        size: const Size(390, 660),
        dark: dark,
      );
    });

    testWidgets('offline strip $d', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 48 * 2);
      addTearDown(tester.view.resetPadding);
      await shot(
        tester,
        'offline_strip_$d',
        ConnectionBanner(
          online: false,
          child: Builder(
            builder: (context) => Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Home', style: TextStyle(fontSize: 28)),
                  ),
                  Expanded(
                    child: ConnectionScope(
                      online: false,
                      child: ErrorState(
                        message: const NetworkFailure().message,
                        onRetry: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        size: const Size(390, 520),
        dark: dark,
      );
    });
  }
}
