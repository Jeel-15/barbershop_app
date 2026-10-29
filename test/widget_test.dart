import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barbershop_app/design_system/design_system.dart';

void main() {
  testWidgets(
    'crest paints through its whole splash timeline (pole, shimmer, glints)',
    (tester) async {
      final c = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 5),
      );
      final pole = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(seconds: 2),
      );
      addTearDown(c.dispose);
      addTearDown(pole.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RosenthalCrest(
              width: 240,
              poleSpin: pole,
              shimmer: c,
              sparkles: c,
            ),
          ),
        ),
      );

      for (final v in [0.0, 0.1, 0.3, 0.5, 0.7, 0.9, 1.0]) {
        c.value = v;
        pole.value = v;
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      expect(
        tester.getSize(find.byType(RosenthalCrest)).height,
        closeTo(240 * RosenthalCrest.aspect, 0.5),
      );
    },
  );

  testWidgets(
    'crest takes its size from the constraints (needed for the Hero flight)',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 40,
              height: 40 * RosenthalCrest.aspect,
              child: RosenthalCrest(),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(RosenthalCrest)).width, 40);
    },
  );
}
