import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/router/app_router.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/auth_fixtures.dart';
import '../../helpers/load_fonts.dart';

/// Real router + real screens + a scripted API. Starts at the splash like the
/// app does, then the test jumps to the page it wants.
Future<(ProviderContainer, GoRouter)> _launch(
  WidgetTester tester,
  AuthHarness h, {
  String? go,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: h.overrides);
  addTearDown(container.dispose);
  final router = container.read(appRouterProvider);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  if (go != null) {
    router.go(go);
    await _route(tester);
  }
  _drainErrors(tester);
  return (container, router);
}

/// A navigation needs a few frames: the route parser is asynchronous.
Future<void> _route(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 800));
  _drainErrors(tester);
}

void _drainErrors(WidgetTester tester) {
  while (tester.takeException() != null) {}
}

Future<void> _pumpFor(
  WidgetTester tester, [
  Duration d = const Duration(milliseconds: 800),
]) async {
  // A few short frames first so async work and route changes can finish.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(d);
  _drainErrors(tester);
}

void main() {
  setUpAll(loadAppFonts);

  group('Sign in screen', () {
    testWidgets('empty fields show messages and make no request', (
      tester,
    ) async {
      final h = await AuthHarness.create();
      await _launch(tester, h, go: '/sign-in');
      await tester.tap(find.text('Sign in').last);
      await _pumpFor(tester);
      expect(find.text('Enter your e-mail address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(h.repo.calls, isEmpty);
    });

    testWidgets(
      'wrong password shows the server sentence and keeps the e-mail',
      (tester) async {
        final repo = FakeAuthRepository()
          ..loginFailure = const UnauthorizedFailure(
            'Invalid email or password.',
          );
        final h = await AuthHarness.create(repo: repo);
        await _launch(tester, h, go: '/sign-in');

        await tester.enterText(
          find.byType(EditableText).first,
          'apitest.admin@rosen.test',
        );
        await tester.enterText(find.byType(EditableText).last, 'wrong');
        await tester.tap(find.text('Sign in').last);
        await _pumpFor(tester);

        expect(find.text('Invalid email or password.'), findsOneWidget);
        expect(find.text('apitest.admin@rosen.test'), findsOneWidget);
      },
    );

    testWidgets('success lands on Home with the greeting and the admin bar', (
      tester,
    ) async {
      final sem = tester.ensureSemantics();
      final h = await AuthHarness.create();
      await _launch(tester, h, go: '/sign-in');

      await tester.enterText(
        find.byType(EditableText).first,
        'apitest.admin@rosen.test',
      );
      await tester.enterText(find.byType(EditableText).last, 'Rosen@12345');
      await tester.tap(find.text('Sign in').last);
      await _pumpFor(tester, const Duration(seconds: 1));

      expect(find.textContaining('API'), findsWidgets); // greeting + first name
      // The bar has icons only; screen readers get the names.
      for (final name in [
        'Dashboard',
        'Appointments',
        'Calendar',
        'More',
        'Invoice',
      ]) {
        expect(find.bySemanticsLabel(name), findsOneWidget, reason: name);
      }
      sem.dispose();
    });

    testWidgets('staff get Me and no New sale / Calendar', (tester) async {
      final sem = tester.ensureSemantics();
      final repo = FakeAuthRepository()..bootstrapResult = staffBootstrap();
      final h = await AuthHarness.create(repo: repo, savedToken: 'saved');
      await _launch(
        tester,
        h,
        go: '/sign-in',
      ); // already signed in -> bounced to the app
      await _pumpFor(tester, const Duration(seconds: 1));

      expect(find.bySemanticsLabel('Me'), findsOneWidget);
      expect(find.bySemanticsLabel('Appointments'), findsOneWidget);
      expect(find.bySemanticsLabel('Calendar'), findsNothing);
      expect(find.bySemanticsLabel('Invoice'), findsNothing);
      sem.dispose();
    });

    testWidgets('an expired session shows the heads-up banner on Sign in', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..bootstrapFailure = const UnauthorizedFailure();
      final h = await AuthHarness.create(repo: repo, savedToken: 'dead');
      await _launch(tester, h, go: '/sign-in');
      expect(find.textContaining('session has ended'), findsOneWidget);
    });
  });

  group('More / Me menu', () {
    testWidgets(
      'lists modules the user can open and signs out after confirming',
      (tester) async {
        final h = await AuthHarness.create(savedToken: 'saved');
        final (container, router) = await _launch(tester, h);
        await _pumpFor(tester, const Duration(seconds: 1));
        router.go('/app/more');
        await _route(tester);

        expect(find.text('Customer'), findsOneWidget);
        expect(find.text('Staff'), findsOneWidget);
        // Flag is off in the fixture, so the entry must not exist.
        expect(find.text('Gallery'), findsNothing);

        // Scroll the list clear of the floating bar before tapping.
        await tester.drag(find.byType(ListView), const Offset(0, -1200));
        await _pumpFor(tester);
        await tester.tap(find.text('Sign out'));
        await _pumpFor(tester);
        await tester.tap(find.text('Sign out').last);
        await _pumpFor(tester, const Duration(seconds: 1));

        expect(container.read(sessionControllerProvider), isA<SignedOut>());
        expect(h.repo.calls, contains('logout'));
      },
    );
  });

  group('Forgot password screen', () {
    testWidgets('e-mail -> code -> new password -> done', (tester) async {
      final h = await AuthHarness.create();
      await _launch(tester, h, go: '/forgot');

      await tester.enterText(
        find.byType(EditableText).first,
        'apitest.admin@rosen.test',
      );
      await tester.tap(find.text('Send code'));
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.textContaining('a***@rosen.test'), findsOneWidget);
      expect(find.textContaining('Resend code in'), findsOneWidget);

      await tester.enterText(find.byType(EditableText).first, '123456');
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('New password'), findsWidgets);

      final fields = find.byType(EditableText);
      await tester.enterText(fields.at(0), 'Secret#12');
      await tester.enterText(fields.at(1), 'Secret#12');
      await _pumpFor(tester);
      await tester.tap(find.text('Save password'));
      await _pumpFor(tester, const Duration(seconds: 1));

      expect(find.text('Password changed'), findsOneWidget);
      expect(
        h.repo.calls,
        containsAllInOrder([
          'forgot:apitest.admin@rosen.test',
          'verify:123456',
          'reset:reset-tok',
        ]),
      );
    });
  });
}
