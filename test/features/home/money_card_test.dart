import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/current_user.dart';
import 'package:barbershop_app/features/home/application/home_controller.dart';
import 'package:barbershop_app/features/home/application/money_visibility.dart';
import 'package:barbershop_app/features/home/presentation/widgets/money_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/home_fixtures.dart';
import '../../helpers/load_fonts.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> raw,
  bool staff = false,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(
        (staff ? staffBootstrap() : adminBootstrap()).user,
      ),
      homeProvider.overrideWith(() => FixedHome(raw)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(body: Center(child: MoneyCard())),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return container;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    // The eye gives a light tap; there is no phone here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
  });

  const today = '2026-10-26';

  testWidgets('admin: the amount is hidden until the eye is tapped', (
    tester,
  ) async {
    await _pump(tester, raw: adminHomeRaw(today: today));
    expect(find.text('TOTAL REVENUE'), findsOneWidget);
    expect(find.text('••••••'), findsOneWidget);
    expect(find.text(r'$713.09'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off_rounded));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text(r'$713.09'), findsOneWidget);
    expect(find.text('••••••'), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('••••••'), findsOneWidget);
  });

  testWidgets('it hides itself again after 60 seconds', (tester) async {
    final c = await _pump(tester, raw: adminHomeRaw(today: today));
    c.read(moneyVisibilityProvider.notifier).reveal();
    await tester.pump(const Duration(seconds: 59));
    expect(c.read(moneyVisibilityProvider), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(c.read(moneyVisibilityProvider), isFalse);
  });

  testWidgets('it hides when the app goes to the background', (tester) async {
    final c = await _pump(tester, raw: adminHomeRaw(today: today));
    c.read(moneyVisibilityProvider.notifier).reveal();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(c.read(moneyVisibilityProvider), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('staff: "My earnings" with commission and tips, also hidden', (
    tester,
  ) async {
    await _pump(tester, raw: emptyStaffHomeRaw(), staff: true);
    expect(find.text('MY EARNINGS'), findsOneWidget);
    expect(find.text('Commission'), findsOneWidget);
    expect(find.text('Tips Received'), findsOneWidget);
    expect(find.text('••••••'), findsNWidgets(3));
    expect(find.text(r'$0.00'), findsNothing);
  });
}
