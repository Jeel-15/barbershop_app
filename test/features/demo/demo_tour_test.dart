import 'package:barbershop_app/features/demo/application/ui_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UiDriver', () {
    Future<void> pumpApp(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    }

    testWidgets('finds a button by its words and presses it for real', (
      tester,
    ) async {
      var taps = 0;
      await pumpApp(
        tester,
        Center(
          child: ElevatedButton(
            onPressed: () => taps++,
            child: const Text('Save Appointment'),
          ),
        ),
      );
      final d = UiDriver();
      final f = await tester.runAsync(
        () => d.locate(const Target(MatchKind.text, 'save appointment')),
      );
      await tester.runAsync(() => d.tapAt(f!.center));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('does not find what is hidden behind a sheet', (tester) async {
      await pumpApp(
        tester,
        Stack(
          children: [
            const Center(child: Text('Hidden')),
            Positioned.fill(child: Container(color: Colors.white)),
          ],
        ),
      );
      final d = UiDriver();
      expect(d.isVisible(const Target(MatchKind.text, 'Hidden')), isFalse);
    });

    testWidgets('picks the highest, lowest or last of several matches', (
      tester,
    ) async {
      await pumpApp(
        tester,
        const Column(
          children: [
            Icon(Icons.add_rounded),
            SizedBox(height: 200),
            Icon(Icons.add_rounded),
          ],
        ),
      );
      final d = UiDriver();
      final hi = await tester.runAsync(
        () => d.locate(
          const Target(MatchKind.icon, 'add_rounded', sel: 'highest'),
        ),
      );
      final lo = await tester.runAsync(
        () => d.locate(
          const Target(MatchKind.icon, 'add_rounded', sel: 'lowest'),
        ),
      );
      expect(hi!.center.dy, lessThan(lo!.center.dy));
    });

    testWidgets('types letter by letter without opening the keyboard', (
      tester,
    ) async {
      final seen = <String>[];
      await pumpApp(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Enter Full Name'),
            onChanged: seen.add,
          ),
        ),
      );
      final d = UiDriver();
      final f = await tester.runAsync(
        () => d.locate(const Target(MatchKind.hint, 'Enter Full Name')),
      );
      await tester.runAsync(() => d.type(f!, 'Olivia', msPerKey: 1));
      await tester.pump();
      expect(seen.last, 'Olivia');
      expect(seen.length, 6);
    });

    testWidgets('points at the whole card, not at the words in it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Center(
          child: Container(
            key: const Key('card'),
            width: 300,
            height: 140,
            alignment: Alignment.topLeft,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('TOTAL REVENUE'),
          ),
        ),
      );
      final d = UiDriver();
      const t = Target(MatchKind.text, 'total revenue', grow: 'card');
      final f = (await tester.runAsync(() => d.locate(t)))!;
      final card = tester.getRect(find.byKey(const Key('card')));
      expect(f.rect.height, lessThan(card.height));
      expect(d.grown(f, t), card);
    });

    testWidgets('points at the whole button when asked for tap', (
      tester,
    ) async {
      await pumpApp(
        tester,
        Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              key: const Key('btn'),
              padding: const EdgeInsets.all(20),
              color: Colors.blue,
              child: const Text('Confirm'),
            ),
          ),
        ),
      );
      final d = UiDriver();
      const t = Target(MatchKind.text, 'Confirm', grow: 'tap');
      final f = (await tester.runAsync(() => d.locate(t)))!;
      expect(d.grown(f, t), tester.getRect(find.byKey(const Key('btn'))));
    });

    testWidgets(
      'finds a control by its accessibility label and by icon choices',
      (tester) async {
        await pumpApp(
          tester,
          Column(
            children: [
              Semantics(
                label: 'Open profile and menu',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
              const Icon(Icons.home_rounded),
            ],
          ),
        );
        final d = UiDriver();
        expect(
          d.isVisible(const Target(MatchKind.label, 'open profile and menu')),
          isTrue,
        );
        // A selected tab shows another icon: either one is found.
        expect(
          d.isVisible(
            const Target(MatchKind.icon, 'home_outlined|home_rounded'),
          ),
          isTrue,
        );
      },
    );

    testWidgets('says so when a control never appears', (tester) async {
      await pumpApp(tester, const SizedBox());
      final d = UiDriver();
      final failed = await tester.runAsync(() async {
        try {
          await d.locate(
            const Target(MatchKind.text, 'Nothing here'),
            timeout: const Duration(milliseconds: 300),
          );
          return false;
        } on TourStepFailed {
          return true;
        }
      });
      expect(failed, isTrue);
    });
  });
}
