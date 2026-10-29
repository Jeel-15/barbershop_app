import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/dev/gallery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/load_fonts.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // Tall surface so the whole (lazy) list is built and any overflow is caught.
  tester.view.physicalSize = const Size(390, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ref.watch(themeModeProvider),
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: c!,
          ),
          home: const GalleryScreen(),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
  return container;
}

void main() {
  setUpAll(() {
    loadAppFonts();
    ShopTime.init();
  });

  testWidgets(
    'the whole design gallery renders in dark with no layout overflow',
    (tester) async {
      await _pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Design gallery'), findsOneWidget);
      expect(find.text('Status pills'), findsOneWidget);
    },
  );

  testWidgets('switching Appearance to Light re-themes live and persists', (
    tester,
  ) async {
    final c = await _pump(tester);
    Color bg() => Theme.of(
      tester.element(find.byType(Scaffold).first),
    ).scaffoldBackgroundColor;
    final darkBg = bg();
    await tester.tap(find.text('Light'));
    await tester.pump(); // starts the theme animation
    await tester.pump(const Duration(milliseconds: 800));
    expect(bg(), isNot(darkBg));
    expect(c.read(themeModeProvider), ThemeMode.light);
    expect(c.read(appPrefsProvider).themeMode, ThemeMode.light);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light theme also renders without overflow', (tester) async {
    final c = await _pump(tester);
    await c.read(themeModeProvider.notifier).set(ThemeMode.light);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large system text (1.6x) still lays out', (tester) async {
    await _pump(tester, textScale: 1.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet / dialog / toast demos work', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Confirm dialog'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Cancel this booking?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pump(const Duration(milliseconds: 800));

    await tester.tap(find.text('Success toast'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved'), findsOneWidget);
  });
}
