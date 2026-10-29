import 'package:barbershop_app/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/load_fonts.dart';
import 'helpers/pump_app.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a row without a photo shows the tile, name and detail', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      PickRow(
        name: 'Skin fade',
        detail: r'$35.00 · 30 min',
        count: 0,
        onTap: () {},
      ),
    );
    expect(find.text('Skin fade'), findsOneWidget);
    expect(find.text(r'$35.00 · 30 min'), findsOneWidget);
    expect(find.byIcon(Icons.content_cut_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a photo is requested at the size shown, the tile stays behind', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      PickRow(
        name: 'Beard trim',
        detail: 'x',
        count: 0,
        imageUrl: 'http://localhost/none.jpg',
        onTap: () {},
      ),
    );
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.width, 56);
    expect(img.height, 56);
    // The test client cannot load it: the tile is still there.
    expect(find.byIcon(Icons.content_cut_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picked: gold tick on the picture and a count badge', (
    tester,
  ) async {
    var taps = 0;
    await pumpThemed(
      tester,
      PickRow(name: 'Men’s cut', detail: 'x', count: 2, onTap: () => taps++),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('× 2'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsNothing);
    await tester.tap(find.text('Men’s cut'));
    expect(taps, 1);
  });

  testWidgets('the placeholder can be another icon (products)', (tester) async {
    await pumpThemed(
      tester,
      PickRow(
        name: 'Hair oil',
        detail: 'x',
        count: 0,
        placeholder: Icons.shopping_bag_outlined,
        onTap: () {},
      ),
    );
    expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
  });

  testWidgets('a long name wraps to two lines without overflow', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      PickRow(
        name: 'The Mister (Men’s Haircut + Facial Detox) with hot towel',
        detail: r'$74.99 · 60 min',
        count: 1,
        onTap: () {},
      ),
      size: const Size(320, 640),
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);
  });
}
