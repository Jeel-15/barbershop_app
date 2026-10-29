import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/load_fonts.dart';

Widget _host(bool online, Widget child, {bool reduce = false}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: ConnectionBanner(
      online: online,
      restoredFor: const Duration(milliseconds: 500),
      child: Scaffold(body: child),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadAppFonts);

  group('ErrorState words', () {
    testWidgets('offline: calm, says the data is safe', (tester) async {
      await tester.pumpWidget(
        _host(false, ErrorState(message: const NetworkFailure().message)),
      );
      await tester.pump();
      expect(find.text('You’re offline'), findsOneWidget);
      expect(find.textContaining('saved info is safe'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('connected but no answer: "Can’t connect right now"', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(true, ErrorState(message: const NetworkFailure().message)),
      );
      await tester.pump();
      expect(find.text('Can’t connect right now'), findsOneWidget);
      expect(find.textContaining('Nothing is lost'), findsOneWidget);
    });

    testWidgets('slow and server problems do not blame the user', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(true, ErrorState(message: const TimeoutFailure().message)),
      );
      await tester.pump();
      expect(find.text('This is taking a while'), findsOneWidget);
      await tester.pumpWidget(
        _host(true, ErrorState(message: const ServerFailure().message)),
      );
      await tester.pump();
      expect(find.text('Our side had a hiccup'), findsOneWidget);
      expect(find.textContaining('wasn’t you'), findsOneWidget);
    });

    testWidgets('a screen’s own title and message are kept', (tester) async {
      await tester.pumpWidget(
        _host(
          true,
          const ErrorState(
            title: 'Could not load times',
            message: 'Pick another day.',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Could not load times'), findsOneWidget);
      expect(find.text('Pick another day.'), findsOneWidget);
    });
  });

  group('ErrorState behaviour', () {
    testWidgets('Try again retries, shows Trying… and comes back', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _host(
          true,
          ErrorState(
            message: 'x',
            onRetry: () => calls++,
            retryFor: const Duration(milliseconds: 300),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Trying…'), findsOneWidget);
      // A second tap while busy does nothing.
      await tester.tap(find.text('Trying…'), warnIfMissed: false);
      expect(calls, 1);
      await _settle(tester);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('retries by itself when the connection comes back', (
      tester,
    ) async {
      var calls = 0;
      final online = ValueNotifier(false);
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: online,
          builder: (_, on, _) => _host(
            on,
            ErrorState(
              message: const NetworkFailure().message,
              onRetry: () => calls++,
              retryFor: const Duration(milliseconds: 200),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(calls, 0);
      online.value = true;
      await tester.pump();
      await tester.pump();
      expect(calls, 1);
      await _settle(tester);
    });

    testWidgets('the support code is folded under Details', (tester) async {
      await tester.pumpWidget(
        _host(true, const ErrorState(message: 'x', supportCode: 'req_123')),
      );
      await tester.pump();
      expect(find.textContaining('req_123'), findsNothing);
      await tester.tap(find.text('Details'));
      await _settle(tester);
      expect(find.textContaining('req_123'), findsOneWidget);
    });

    testWidgets('with animations off nothing keeps moving', (tester) async {
      await tester.pumpWidget(
        _host(true, ErrorState(message: 'x', onRetry: () {}), reduce: true),
      );
      await tester.pump();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
  });

  group('ConnectionBanner', () {
    testWidgets('offline shows the strip; back online says so, then folds', (
      tester,
    ) async {
      final online = ValueNotifier(true);
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: online,
          builder: (_, on, _) => _host(on, const Text('page')),
        ),
      );
      await tester.pump();
      expect(find.textContaining('offline'), findsNothing);

      online.value = false;
      await _settle(tester);
      expect(find.text("You're offline. Showing saved data."), findsOneWidget);

      online.value = true;
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Back online'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await _settle(tester);
      expect(find.text('Back online'), findsNothing);
      expect(find.text('page'), findsOneWidget);
    });

    testWidgets('the page keeps its state when the strip comes and goes', (
      tester,
    ) async {
      final online = ValueNotifier(true);
      final ctrl = TextEditingController();
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: online,
          builder: (_, on, _) => _host(on, TextField(controller: ctrl)),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'hello');
      final state = tester.state(find.byType(TextField));
      online.value = false;
      await _settle(tester);
      online.value = true;
      await _settle(tester);
      expect(tester.state(find.byType(TextField)), same(state));
      expect(ctrl.text, 'hello');
    });

    testWidgets('starting offline shows the strip at once', (tester) async {
      await tester.pumpWidget(_host(false, const Text('page')));
      await tester.pump();
      expect(find.text("You're offline. Showing saved data."), findsOneWidget);
    });
  });
}
