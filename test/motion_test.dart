import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {bool reduce = false}) => MaterialApp(
  theme: AppTheme.dark,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: Scaffold(body: child),
  ),
);

void main() {
  group('SoftSwitcher', () {
    testWidgets('cross-fades to the new view and drops the old one', (
      tester,
    ) async {
      Widget view(String k) => SoftSwitcher(
        child: KeyedSubtree(key: ValueKey(k), child: Text(k)),
      );
      await tester.pumpWidget(_app(view('a')));
      expect(find.text('a'), findsOneWidget);
      await tester.pumpWidget(_app(view('b')));
      await tester.pump(const Duration(milliseconds: 100));
      // Mid-way both are there.
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('a'), findsNothing);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('with animations off it just switches', (tester) async {
      Widget view(String k) => SoftSwitcher(
        child: KeyedSubtree(key: ValueKey(k), child: Text(k)),
      );
      await tester.pumpWidget(_app(view('a'), reduce: true));
      await tester.pumpWidget(_app(view('b'), reduce: true));
      expect(find.text('a'), findsNothing);
      expect(find.text('b'), findsOneWidget);
    });
  });

  group('StaggerIn', () {
    Widget list({required Object resetKey, int rows = 3}) => _app(
      EntranceHost(
        resetKey: resetKey,
        child: Column(
          children: [
            for (var i = 0; i < rows; i++)
              StaggerIn(index: i, child: Text('row $i')),
          ],
        ),
      ),
    );

    testWidgets('rows of a fresh list start hidden and come in', (
      tester,
    ) async {
      await tester.pumpWidget(list(resetKey: 1));
      FadeTransition fade(int i) => tester.widget<FadeTransition>(
        find.descendant(
          of: find.byType(StaggerIn).at(i),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade(2).opacity.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 600));
      expect(fade(2).opacity.value, 1);
    });

    testWidgets('a row built after the list opened appears at once', (
      tester,
    ) async {
      await tester.pumpWidget(list(resetKey: 1, rows: 1));
      await tester.pump(const Duration(milliseconds: 700));
      // The same list grows (paging): the new row is not animated.
      await tester.pumpWidget(list(resetKey: 1, rows: 2));
      expect(
        find.descendant(
          of: find.byType(StaggerIn).at(1),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });
  });

  group('success', () {
    testWidgets('the check draws itself and settles', (tester) async {
      await tester.pumpWidget(
        _app(const Center(child: AnimatedCheck(color: Colors.green))),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(AnimatedCheck), findsOneWidget);
    });

    testWidgets('the burst plays over the screen and removes itself', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      showSuccessBurst(ctx, label: 'Saved');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Saved'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1400));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Saved'), findsNothing);
    });

    testWidgets('a success toast carries the animated check', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      showToast(ctx, 'Done', kind: ToastKind.success);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnimatedCheck), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });

  testWidgets('PulseDot animates and stops with animations off', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const PulseDot(color: Colors.red)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(
      _app(const PulseDot(color: Colors.red), reduce: true),
    );
    await tester.pump();
  });
}
