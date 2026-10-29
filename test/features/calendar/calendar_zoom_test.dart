import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/calendar/application/calendar_controller.dart';
import 'package:barbershop_app/features/calendar/domain/calendar_models.dart';
import 'package:barbershop_app/features/calendar/presentation/widgets/day_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/calendar_fixtures.dart';
import '../../helpers/load_fonts.dart';

const _availability = DayAvailability(
  openMin: 9 * 60,
  closeMin: 20 * 60,
  shopDayOff: false,
  staff: {
    42: StaffDay(isDayOff: false, hours: [(540, 780), (840, 1200)]),
    49: StaffDay(isDayOff: false, hours: [(540, 900)]),
  },
);

class _Probe {
  final zooms = <double>[];
  final slots = <(int, int)>[];
  var hintSeen = 0;
}

Widget _app(_Probe p, {double zoom = kHourDefault, bool hint = false}) {
  final day = calendarWindow(
    '2026-10-25',
  ).day(DateTime(2026, 10, 25), _availability);
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: DayGrid(
        day: day,
        date: DateTime(2026, 10, 25),
        zoom: zoom,
        onZoom: p.zooms.add,
        showHint: hint,
        onHintSeen: () => p.hintSeen++,
        onEventTap: (_) {},
        onSlotTap: (l, m) => p.slots.add((l, m)),
      ),
    ),
  );
}

Future<_Probe> _grid(
  WidgetTester tester, {
  double zoom = kHourDefault,
  bool hint = false,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final p = _Probe();
  await tester.pumpWidget(_app(p, zoom: zoom, hint: hint));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  while (tester.takeException() != null) {}
  return p;
}

/// One hour in pixels: the distance between two neighbouring hour labels.
double _hourPx(WidgetTester tester) =>
    tester.getCenter(find.text('1 PM')).dy -
    tester.getCenter(find.text('12 PM')).dy;

Future<(TestGesture, TestGesture)> _twoFingers(
  WidgetTester tester,
  Offset center,
  double gap,
) async {
  final a = await tester.startGesture(center - Offset(0, gap / 2));
  final b = await tester.startGesture(center + Offset(0, gap / 2));
  await tester.pump();
  return (a, b);
}

/// Moves the fingers apart (or together, when negative) by [by] px in total.
Future<void> _spread(
  WidgetTester tester,
  (TestGesture, TestGesture) f,
  double by,
) async {
  const steps = 8;
  for (var i = 0; i < steps; i++) {
    await f.$1.moveBy(Offset(0, -by / 2 / steps));
    await f.$2.moveBy(Offset(0, by / 2 / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _lift(WidgetTester tester, (TestGesture, TestGesture) f) async {
  await f.$1.up();
  await f.$2.up();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('spreading two fingers makes the hours taller', (tester) async {
    final p = await _grid(tester);
    expect(_hourPx(tester), closeTo(88, 0.6));
    final f = await _twoFingers(tester, const Offset(220, 500), 120);
    await _spread(tester, f, 120); // 120 -> 240 apart = 2x
    expect(_hourPx(tester), closeTo(176, 1.5));
    await _lift(tester, f);
    expect(p.zooms.single, closeTo(176, 1.5));
  });

  testWidgets('pinching in makes them shorter, and stops at the limits', (
    tester,
  ) async {
    final p = await _grid(tester);
    final f = await _twoFingers(tester, const Offset(220, 500), 300);
    await _spread(tester, f, -290);
    expect(_hourPx(tester), closeTo(kHourMin, 0.6));
    await _lift(tester, f);
    expect(p.zooms.single, kHourMin);

    final g = await _twoFingers(tester, const Offset(220, 500), 40);
    await _spread(tester, g, 600);
    expect(_hourPx(tester), closeTo(kHourMax, 0.6));
    await _lift(tester, g);
  });

  testWidgets('the time under the fingers stays under the fingers', (
    tester,
  ) async {
    await _grid(tester);
    await tester.drag(find.byType(DayGrid), const Offset(0, -150));
    await tester.pump(const Duration(milliseconds: 400));
    const centre = Offset(220, 500);
    final before = tester.getCenter(find.text('1 PM')).dy - centre.dy;
    final f = await _twoFingers(tester, centre, 100);
    await _spread(tester, f, 100); // 2x
    final after = tester.getCenter(find.text('1 PM')).dy - centre.dy;
    // The distance from the fingers to 1 PM doubles with the zoom.
    expect(after, closeTo(before * 2, 4));
    await _lift(tester, f);
  });

  testWidgets('a pinch does not mark a slot; a tap afterwards still does', (
    tester,
  ) async {
    final p = await _grid(tester);
    final f = await _twoFingers(tester, const Offset(220, 450), 100);
    await _spread(tester, f, 60);
    await f.$1.up();
    await f.$2.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(p.slots, isEmpty);
    final top = tester.getTopLeft(find.byType(DayGrid));
    final y = tester.getCenter(find.text('2 PM')).dy + 14;
    // The first tap marks the free spot, the second opens the form.
    await tester.tapAt(Offset(top.dx + DayGrid.gutter + 40, y));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(Offset(top.dx + DayGrid.gutter + 40, y));
    await tester.pump(const Duration(milliseconds: 100));
    expect(p.slots.length, 1);
  });

  testWidgets('tapping maps to the right minute at another zoom', (
    tester,
  ) async {
    final p = await _grid(tester, zoom: 132);
    expect(_hourPx(tester), closeTo(132, 0.6));
    final top = tester.getTopLeft(find.byType(DayGrid));
    // The label is centred 7 px above its hour line; 14:30 is half an hour below.
    final y = tester.getCenter(find.text('2 PM')).dy + 7 + 66 + 3;
    await tester.tapAt(Offset(top.dx + DayGrid.gutter + 40, y));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(Offset(top.dx + DayGrid.gutter + 40, y));
    await tester.pump(const Duration(milliseconds: 100));
    expect(p.slots.single.$2, 14 * 60 + 30);
  });

  testWidgets('a value from outside (the zoom button) glides to it', (
    tester,
  ) async {
    final p = await _grid(tester);
    await tester.pumpWidget(_app(p, zoom: 132));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final mid = _hourPx(tester);
    expect(mid, greaterThan(88));
    expect(mid, lessThan(132));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_hourPx(tester), closeTo(132, 0.6));
  });

  testWidgets('the pill shows the level and goes back to 1x when tapped', (
    tester,
  ) async {
    final p = await _grid(tester);
    final f = await _twoFingers(tester, const Offset(220, 500), 100);
    await _spread(tester, f, 80); // 1.8x
    expect(find.text('1.8x'), findsOneWidget);
    await f.$1.up();
    await f.$2.up();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('1.8x'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(p.zooms.last, kHourDefault);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('one finger still scrolls, and the tip closes on first pinch', (
    tester,
  ) async {
    final p = await _grid(tester, hint: true);
    expect(find.text('Pinch with two fingers to zoom the day'), findsOneWidget);
    final y0 = tester.getCenter(find.text('1 PM')).dy;
    await tester.drag(find.byType(DayGrid), const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getCenter(find.text('1 PM')).dy, lessThan(y0));
    final f = await _twoFingers(tester, const Offset(220, 500), 100);
    expect(p.hintSeen, 1);
    await _lift(tester, f);
  });

  testWidgets('the extreme zooms build without errors', (tester) async {
    await _grid(tester, zoom: kHourMax);
    expect(tester.takeException(), isNull);
    await _grid(tester, zoom: kHourMin);
    expect(tester.takeException(), isNull);
  });
}
