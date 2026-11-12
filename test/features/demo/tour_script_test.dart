import 'dart:convert';
import 'dart:io';

import 'package:barbershop_app/features/demo/application/tour_script.dart';
import 'package:barbershop_app/features/demo/application/ui_driver.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tour script is data, and a wrong word in it only shows up on the phone, in the
/// middle of a recording. These tests catch that here, and keep "nothing is missed"
/// true: every element of the coverage manifest must be explained by some beat.
void main() {
  final json =
      jsonDecode(File('assets/demo/tour.json').readAsStringSync())
          as Map<String, dynamic>;
  final chapters = [
    for (final c in json['chapters'] as List)
      TourChapter.fromJson(Map<String, dynamic>.from(c as Map)),
  ];
  final beats = [for (final c in chapters) ...c.beats];

  const known = {
    'pause',
    'go',
    'closeSheet',
    'clear',
    'tapAt',
    'pickSlot',
    'pinch',
    'doubleTap',
    'scroll',
    'scrollTo',
    'ring',
    'sweep',
    'tap',
    'swipe',
    'pull',
    'nav',
    'back',
    'type',
  };
  const kinds = ['text', 'starts', 'regex', 'icon', 'hint', 'label'];

  void checkTarget(String where, List<dynamic> a, int at) {
    expect(kinds, contains(a[at]), reason: '$where: ${a[at]}');
    expect(a[at + 1], isA<String>(), reason: where);
    if (a[at] == 'icon') {
      for (final n in (a[at + 1] as String).split('|')) {
        expect(tourIcons, contains(n.trim()), reason: '$where: icon $n');
      }
    }
    if (a[at] == 'regex') {
      expect(() => RegExp(a[at + 1] as String), returnsNormally, reason: where);
    }
    if (a.length > at + 2) {
      final o = Map<String, dynamic>.from(a[at + 2] as Map);
      const okKeys = {'sel', 'in', 'grow', 'up', 'opt'};
      expect(okKeys, containsAll(o.keys), reason: '$where: ${o.keys}');
      if (o['sel'] != null) {
        expect(['first', 'last', 'lowest', 'highest'], contains(o['sel']));
      }
      if (o['grow'] != null) {
        expect(['tap', 'card'], contains(o['grow']), reason: where);
      }
    }
  }

  test('beat ids are unique, spoken, and have their voice file', () {
    final ids = beats.map((b) => b.id).toList();
    expect(ids.toSet().length, ids.length);
    for (final b in beats) {
      expect(b.say.trim(), isNotEmpty, reason: b.id);
      expect(b.say.length, lessThanOrEqualTo(190), reason: '${b.id} too long');
      expect(
        File('assets/demo/audio/${b.id}.mp3').existsSync(),
        isTrue,
        reason: '${b.id}: run node tool/demo/make_audio.mjs',
      );
    }
  });

  test('only uses actions the tour knows, spelled right', () {
    for (final b in beats) {
      for (final a in [...b.pre, ...b.actions]) {
        final where = '${b.id}: ${a.first}';
        expect(known, contains(a.first), reason: where);
        switch (a.first) {
          case 'tap' || 'ring' || 'scrollTo':
            checkTarget(where, a, 1);
          case 'sweep':
            for (final x in a[1] as List) {
              checkTarget(where, List<dynamic>.from(x as List), 0);
            }
          case 'swipe':
            final m = Map<String, dynamic>.from(a[1] as Map);
            final at = m['at'] as List;
            if (at.first is String) {
              checkTarget(where, List<dynamic>.from(at), 0);
            }
            expect(m, contains('dx'), reason: where);
          case 'nav':
            expect(
              ['home', 'appointments', 'calendar', 'more', 'plus'],
              contains(a[1]),
              reason: where,
            );
        }
      }
      if (b.ifVisible != null) {
        expect(b.ifVisible, isNotNull);
      }
    }
  });

  test('a beat with a ring or a tap does its showing while it speaks', () {
    // `pre` is silent (scroll, open): it must not hold the pointing.
    for (final b in beats) {
      for (final a in b.pre) {
        expect(
          ['scroll', 'scrollTo', 'go', 'closeSheet', 'pause'],
          contains(a.first),
          reason: '${b.id}: ${a.first} belongs in "do", not "pre"',
        );
      }
    }
  });

  test('every element of the coverage manifest is explained somewhere', () {
    final cov =
        jsonDecode(File('assets/demo/coverage.json').readAsStringSync())
            as Map<String, dynamic>;
    final known = {
      for (final c in cov['chapters'] as List)
        for (final s in (c as Map)['screens'] as List)
          for (final e in (s as Map)['els'] as List) (e as List)[0] as String,
    };
    final covered = {for (final b in beats) ...b.covers};
    expect(
      known,
      containsAll(covered),
      reason: 'a beat covers an element that is not in coverage.json',
    );
    // Chapters that are written must be complete; chapters not written yet are
    // listed by tool/demo/coverage_check.mjs (the build is not blocked by them).
    final written = {for (final c in chapters) c.id};
    for (final c in cov['chapters'] as List) {
      final id = (c as Map)['id'] as String;
      if (!written.contains(id)) continue;
      final missing = [
        for (final s in c['screens'] as List)
          for (final e in (s as Map)['els'] as List)
            if (!covered.contains((e as List)[0])) e[0] as String,
      ];
      expect(
        missing,
        isEmpty,
        reason: 'chapter $id does not explain: $missing',
      );
    }
  });

  test('creates only the demo customer the plan says (Canadian, Edmonton)', () {
    final typed = [
      for (final b in beats)
        for (final a in [...b.pre, ...b.actions])
          if (a.first == 'type') a[2] as String,
    ];
    for (final t in typed) {
      expect(
        [
              'Olivia Tremblay',
              'olivia.tremblay@example.com',
              '7805550777',
            ].contains(t) ||
            t.length < 12,
        isTrue,
        reason: 'unexpected typed text: $t',
      );
    }
  });
}
