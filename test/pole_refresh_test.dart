import 'dart:async';

import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/load_fonts.dart';

Widget _app(Future<void> Function() onRefresh, {bool reduce = false}) =>
    MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(
          body: AppRefresh(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 3; i++)
                  SizedBox(height: 120, child: Text('row $i')),
              ],
            ),
          ),
        ),
      ),
    );

PoleRefreshFace _face(WidgetTester tester) =>
    tester.widget<PoleRefreshFace>(find.byType(PoleRefreshFace));

/// Lets time pass in frames (the indicator moves in steps: end of the scroll,
/// settling, loading).
Future<void> _wait(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Holds the finger down and drags it [px] downward in small steps.
Future<TestGesture> _pull(WidgetTester tester, double px) async {
  final g = await tester.startGesture(const Offset(200, 300));
  for (var moved = 0.0; moved < px; moved += 20) {
    await g.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
  }
  return g;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    ShopTime.init();
    ShopTime.clock = () => DateTime.utc(2026, 10, 27, 20, 41); // 2:41 PM
  });

  testWidgets('a short pull shows the pole turning, and does not refresh', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(_app(() async => calls++));
    final g = await _pull(tester, 40);
    expect(_face(tester).mode, PoleMode.pulling);
    expect(find.text('Pull to refresh'), findsOneWidget);
    await g.up();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 0);
  });

  testWidgets('the stripes follow the finger, both ways', (tester) async {
    await tester.pumpWidget(_app(() async {}));
    final g = await tester.startGesture(const Offset(200, 300));
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    await g.moveBy(const Offset(0, 20));
    await tester.pump();
    final near = _face(tester).phase;
    await g.moveBy(const Offset(0, 30));
    await tester.pump();
    final far = _face(tester).phase;
    expect(far, greaterThan(near));
    await g.moveBy(const Offset(0, -30));
    await tester.pump();
    expect(_face(tester).phase, lessThan(far));
    await g.up();
    await _wait(tester, 3000);
  });

  testWidgets('pulled far enough it says Release, taps, then refreshes', (
    tester,
  ) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final done = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      _app(() {
        calls++;
        return done.future;
      }),
    );
    final g = await _pull(tester, 140);
    expect(_face(tester).mode, PoleMode.armed);
    expect(find.text('Release to refresh'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.selectionClick']); // once, on arming
    expect(calls, 0); // not before the finger lifts

    await g.up();
    await _wait(tester, 400);
    expect(calls, 1);
    expect(_face(tester).mode, PoleMode.loading);
    expect(find.text('Refreshing…'), findsOneWidget);

    // The pole is turning while it loads.
    final p1 = _face(tester).phase;
    await _wait(tester, 250);
    expect(_face(tester).phase, greaterThan(p1));

    done.complete();
    await _wait(tester, 700);
    expect(_face(tester).mode, PoleMode.success);
    expect(find.text('Updated 2:41 PM'), findsOneWidget);

    await _wait(tester, 3000);
    // At rest nothing of it is built.
    expect(find.byType(PoleRefreshFace), findsNothing);
    // The next pull remembers the last result: a small line under the words.
    final g2 = await _pull(tester, 40);
    expect(find.text('Pull to refresh'), findsOneWidget);
    expect(find.text('Updated 2:41 PM'), findsOneWidget);
    await g2.up();
    await _wait(tester, 800);
  });

  testWidgets('an instant refresh is still seen turning for a moment', (
    tester,
  ) async {
    await tester.pumpWidget(_app(() async {}));
    final g = await _pull(tester, 140);
    await g.up();
    await _wait(tester, 300);
    // The data is already there, the pole is not done yet.
    expect(_face(tester).mode, PoleMode.loading);
    await _wait(tester, 700);
    expect(_face(tester).mode, PoleMode.success);
    await _wait(tester, 3000);
  });

  testWidgets('a failing refresh says so and does not throw', (tester) async {
    await tester.pumpWidget(_app(() async => throw StateError('offline')));
    final g = await _pull(tester, 140);
    await g.up();
    await _wait(tester, 1000);
    expect(tester.takeException(), isNull);
    expect(_face(tester).mode, PoleMode.failure);
    expect(find.text("Couldn't refresh"), findsOneWidget);
    await _wait(tester, 3000);
  });

  testWidgets(
    'with animations off the pole does not move, the words still do',
    (tester) async {
      await tester.pumpWidget(_app(() async {}, reduce: true));
      final g = await _pull(tester, 140);
      expect(_face(tester).reduceMotion, isTrue);
      expect(find.text('Release to refresh'), findsOneWidget);
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      final p = _face(tester).phase;
      await tester.pump(const Duration(milliseconds: 200));
      expect(_face(tester).phase, p);
      await _wait(tester, 3000);
    },
  );
}
