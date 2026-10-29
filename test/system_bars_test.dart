import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

SystemUiOverlayStyle _styleOf(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    )
    .value;

Future<void> _pump(WidgetTester tester, ThemeData theme, {bool? light}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: SystemBars(lightIcons: light, child: const Scaffold()),
      ),
    );

void main() {
  testWidgets('a dark screen gets light icons', (tester) async {
    await _pump(tester, AppTheme.dark);
    final s = _styleOf(tester);
    expect(s.statusBarIconBrightness, Brightness.light);
    expect(s.systemNavigationBarIconBrightness, Brightness.light);
    expect(s.statusBarBrightness, Brightness.dark); // iOS reads it reversed
  });

  testWidgets('a light screen gets dark icons, so they can be seen', (
    tester,
  ) async {
    await _pump(tester, AppTheme.light);
    final s = _styleOf(tester);
    expect(s.statusBarIconBrightness, Brightness.dark);
    expect(s.systemNavigationBarIconBrightness, Brightness.dark);
    expect(s.statusBarBrightness, Brightness.light);
  });

  testWidgets('a screen that is always dark overrides a light theme', (
    tester,
  ) async {
    await _pump(tester, AppTheme.light, light: true);
    expect(_styleOf(tester).statusBarIconBrightness, Brightness.light);
  });

  testWidgets('the bars are transparent, the screen shows under them', (
    tester,
  ) async {
    await _pump(tester, AppTheme.dark);
    final s = _styleOf(tester);
    expect(s.statusBarColor, Colors.transparent);
    expect(s.systemNavigationBarColor, Colors.transparent);
    expect(s.systemStatusBarContrastEnforced, isFalse);
    expect(s.systemNavigationBarContrastEnforced, isFalse);
  });

  group('page transition', pageTransitionTests);
}

void pageTransitionTests() {
  testWidgets(
    'a screen that rises keeps its own background still under it (no strip)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('next')),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump(const Duration(milliseconds: 100));
      // The rising content (SlideTransition) sits inside a still background.
      expect(
        find.descendant(
          of: find.byType(ColoredBox),
          matching: find.byType(SlideTransition),
        ),
        findsWidgets,
      );
      await tester.pumpAndSettle();
      expect(find.text('next'), findsOneWidget);
    },
  );
}
