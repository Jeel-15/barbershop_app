import 'package:barbershop_app/features/shell/back_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe {
  _Probe({required this.atHome});

  bool atHome;
  var homes = 0;
  var hints = 0;
  var exits = 0;
  var clock = DateTime(2026, 11, 5, 10);
}

Future<void> _pump(WidgetTester tester, _Probe p) => tester.pumpWidget(
  MaterialApp(
    home: ShellBackHandler(
      atHome: p.atHome,
      onHome: () => p.homes++,
      onHint: () => p.hints++,
      onExit: () => p.exits++,
      now: () => p.clock,
      child: const Scaffold(body: Text('tabs')),
    ),
  ),
);

void main() {
  testWidgets('back on another tab goes to Home and never leaves the app', (
    tester,
  ) async {
    final p = _Probe(atHome: false);
    await _pump(tester, p);
    await tester.binding.handlePopRoute();
    await tester.binding.handlePopRoute();
    expect(p.homes, 2);
    expect(p.exits, 0);
    expect(p.hints, 0);
  });

  testWidgets('on Home the first back only hints, a second within 2 s exits', (
    tester,
  ) async {
    final p = _Probe(atHome: true);
    await _pump(tester, p);
    await tester.binding.handlePopRoute();
    expect((p.hints, p.exits), (1, 0));
    p.clock = p.clock.add(const Duration(milliseconds: 1500));
    await tester.binding.handlePopRoute();
    expect((p.hints, p.exits), (1, 1));
  });

  testWidgets('a second back after 2 s is a new first press', (tester) async {
    final p = _Probe(atHome: true);
    await _pump(tester, p);
    await tester.binding.handlePopRoute();
    p.clock = p.clock.add(const Duration(seconds: 3));
    await tester.binding.handlePopRoute();
    expect((p.hints, p.exits), (2, 0));
  });

  testWidgets('coming back from another tab forgets an old first press', (
    tester,
  ) async {
    final p = _Probe(atHome: true);
    await _pump(tester, p);
    await tester.binding.handlePopRoute(); // hint
    p.atHome = false;
    await _pump(tester, p);
    await tester.binding.handlePopRoute(); // to Home
    p.atHome = true;
    await _pump(tester, p);
    p.clock = p.clock.add(const Duration(milliseconds: 500));
    await tester.binding.handlePopRoute(); // first press again, not an exit
    expect(p.exits, 0);
    expect(p.hints, 2);
  });
}
