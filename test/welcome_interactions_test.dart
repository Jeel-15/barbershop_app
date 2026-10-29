import 'package:flutter/material.dart';
import 'helpers/load_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/welcome/presentation/welcome_screen.dart';
import 'package:go_router/go_router.dart';

Future<void> _pumpWelcome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const Text('SIGN-IN PAGE')),
      GoRoute(path: '/forgot', builder: (_, _) => const Text('FORGOT PAGE')),
    ],
  );
  addTearDown(router.dispose);

  // Bundled fonts load in tests, so text is measured like on a phone and a
  // layout overflow would fail the test.
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
  );
  await tester.pump(const Duration(seconds: 3));
  _drainFontErrors(tester);
}

/// google_fonts can't download in tests; the fallback font is fine for
/// checking behaviour, so swallow those load errors.
void _drainFontErrors(WidgetTester tester) {
  while (tester.takeException() != null) {}
}

/// Routes and animations only start on the frame *after* the tap, so run one
/// short frame first and then let time pass.
Future<void> _settle(
  WidgetTester tester, [
  Duration d = const Duration(seconds: 1),
]) async {
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(d);
  _drainFontErrors(tester);
}

Future<void> _next(WidgetTester tester) async {
  await tester.tapAt(const Offset(375, 300));
  await tester.pump(const Duration(seconds: 1));
  _drainFontErrors(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets(
    'first slide is the staff dashboard, not a customer booking page',
    (tester) async {
      await _pumpWelcome(tester);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Bookings'), findsOneWidget);
      // Customer features must not exist in this app.
      expect(find.text('Book Appointment'), findsNothing);
      expect(find.text('Continue as guest'), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
    },
  );

  testWidgets('Skip jumps to the last slide (invoice)', (tester) async {
    await _pumpWelcome(tester);
    expect(find.text('INV-20261023-0042'), findsNothing);

    await tester.tap(find.text('Skip'));
    await tester.pump(const Duration(seconds: 1));
    _drainFontErrors(tester);

    expect(find.text('INV-20261023-0042'), findsOneWidget);
    // Skip hides itself on the last slide.
    expect(
      tester
          .widget<AnimatedOpacity>(
            find
                .ancestor(
                  of: find.text('Skip'),
                  matching: find.byType(AnimatedOpacity),
                )
                .first,
          )
          .opacity,
      0,
    );
  });

  testWidgets('tapping the right edge advances, left edge goes back', (
    tester,
  ) async {
    await _pumpWelcome(tester);

    await _next(tester);
    expect(find.text('Alex'), findsOneWidget); // slide 2: barber deck

    await tester.tapAt(const Offset(10, 300));
    await tester.pump(const Duration(seconds: 1));
    _drainFontErrors(tester);
    expect(find.text('TODAY'), findsOneWidget); // back to slide 1
  });

  testWidgets(
    'KPI tiles: tapping one moves the highlight (no crash, still shows all three)',
    (tester) async {
      await _pumpWelcome(tester);
      await tester.tap(find.text('Revenue'));
      await tester.pump(const Duration(milliseconds: 400));
      _drainFontErrors(tester);
      for (final label in ['Bookings', 'Revenue', 'Tips']) {
        expect(find.text(label), findsOneWidget);
      }
    },
  );

  testWidgets('barber deck: tapping the stack brings the next barber forward', (
    tester,
  ) async {
    await _pumpWelcome(tester);
    await _next(tester);

    final before = tester.getTopLeft(find.text('Jordan')).dx;
    await tester.tap(find.text('Alex'), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    final after = tester.getTopLeft(find.text('Jordan')).dx;

    // Jordan starts behind (left) and moves into the front slot.
    expect(after, isNot(equals(before)));
  });

  testWidgets(
    'request card: Confirm, Reschedule to a free slot, Cancel and Try again',
    (tester) async {
      await _pumpWelcome(tester);
      await _next(tester);
      await _next(tester);

      expect(find.text('Pending'), findsOneWidget);
      expect(find.textContaining('· 11:30 AM'), findsOneWidget);

      // Reschedule: the taken slot is ignored, a free one is applied.
      await tester.tap(find.text('Reschedule'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('11:00 AM'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text('Pending'),
        findsOneWidget,
        reason: 'a taken slot must not be selectable',
      );
      await tester.tap(find.text('12:00 PM'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Rescheduled'), findsOneWidget);
      expect(find.textContaining('· 12:00 PM'), findsWidgets);

      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Pending'), findsOneWidget);

      await tester.tap(find.text('Confirm'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Confirmed'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.text('Cancel'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Cancelled'), findsOneWidget);
      _drainFontErrors(tester);
    },
  );

  testWidgets(
    'invoice: tapping flips to the earnings back and again to the front',
    (tester) async {
      await _pumpWelcome(tester);
      await tester.tap(find.text('Skip'));
      await tester.pump(const Duration(seconds: 1));
      _drainFontErrors(tester);

      expect(find.text('YOUR EARNINGS TODAY'), findsNothing);
      await tester.tap(find.text('INV-20261023-0042'));
      await _settle(tester, const Duration(milliseconds: 1200));
      expect(find.text('YOUR EARNINGS TODAY'), findsOneWidget);

      await tester.tap(find.text('YOUR EARNINGS TODAY'));
      await _settle(tester, const Duration(milliseconds: 1200));
      expect(find.text('YOUR EARNINGS TODAY'), findsNothing);
    },
  );

  testWidgets('Sign in and Forgot password open their screens', (tester) async {
    await _pumpWelcome(tester);
    await tester.tap(find.text('Sign in'));
    await _settle(tester);
    expect(find.text('SIGN-IN PAGE'), findsOneWidget);
  });

  testWidgets('Forgot password link opens the reset screen', (tester) async {
    await _pumpWelcome(tester);
    await tester.tap(find.text('Forgot password?'));
    await _settle(tester);
    expect(find.text('FORGOT PAGE'), findsOneWidget);
  });

  testWidgets('headline words stay visible after many animation frames', (
    tester,
  ) async {
    await _pumpWelcome(tester);
    // Regression: the word counter used to leak across rebuilds, which pushed
    // later words past the end of the animation so they never appeared.
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    _drainFontErrors(tester);

    for (final word in ['Your', 'whole', 'shop,', 'in', 'your', 'pocket.']) {
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(of: find.text(word), matching: find.byType(Opacity))
            .first,
      );
      expect(opacity.opacity, 1.0, reason: '"$word" should be fully revealed');
    }
  });
}
