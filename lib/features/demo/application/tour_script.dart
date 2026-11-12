import 'package:barbershop_app/features/demo/application/ui_driver.dart';

/// One sentence of the tour, spoken once, with what the screen does while it is said.
///
/// A beat is the smallest unit: one sentence, one voice file, and the actions that
/// show exactly what the sentence is about. `pre` runs silently BEFORE the voice
/// (scroll to the thing, open the screen), `do` runs WHILE the voice speaks.
class TourBeat {
  TourBeat({
    required this.id,
    required this.say,
    this.cap,
    this.pre = const [],
    this.actions = const [],
    this.covers = const [],
    this.quick = false,
    this.ifVisible,
  });

  factory TourBeat.fromJson(Map<String, dynamic> j) => TourBeat(
    id: j['id'] as String,
    say: j['say'] as String,
    cap: j['cap'] as String?,
    pre: _actions(j['pre']),
    actions: _actions(j['do']),
    covers: [for (final c in (j['covers'] as List? ?? const [])) c as String],
    quick: j['quick'] == true,
    ifVisible: j['if'] == null
        ? null
        : parseTarget(List<dynamic>.from(j['if'] as List), 0),
  );

  final String id;

  /// What the voice says (also the subtitle unless [cap] is given).
  final String say;
  final String? cap;
  final List<List<dynamic>> pre;
  final List<List<dynamic>> actions;

  /// The coverage-manifest elements this sentence explains.
  final List<String> covers;

  /// In the short version of the tour.
  final bool quick;

  /// The beat is skipped (voice and all) when this is not on screen: for things that
  /// depend on the time of day or the data (e.g. "Next up").
  final Target? ifVisible;

  String get subtitle => cap ?? say;
}

class TourChapter {
  TourChapter({
    required this.id,
    required this.name,
    required this.start,
    required this.ready,
    required this.beats,
  });

  factory TourChapter.fromJson(Map<String, dynamic> j) => TourChapter(
    id: j['id'] as String,
    name: j['name'] as String,
    start: j['start'] as String,
    ready: j['ready'] == null
        ? null
        : parseTarget(List<dynamic>.from(j['ready'] as List), 0),
    beats: [
      for (final b in (j['beats'] as List))
        TourBeat.fromJson(Map<String, dynamic>.from(b as Map)),
    ],
  );

  final String id;
  final String name;

  /// Where the chapter begins (a route).
  final String start;

  /// What must be on screen before the first beat.
  final Target? ready;
  final List<TourBeat> beats;
}

List<List<dynamic>> _actions(Object? raw) => [
  for (final a in (raw as List? ?? const [])) List<dynamic>.from(a as List),
];

/// `["text", "Total revenue", {"grow": "card", "sel": "lowest", "in": "Card", "up": 1, "opt": true}]`
/// starting at index [at] of [a] (kind, value, optional options).
Target parseTarget(List<dynamic> a, int at) {
  final kind = switch (a[at] as String) {
    'text' => MatchKind.text,
    'starts' => MatchKind.textStarts,
    'regex' => MatchKind.regex,
    'icon' => MatchKind.icon,
    'label' => MatchKind.label,
    _ => MatchKind.hint,
  };
  final opts = a.length > at + 2 && a[at + 2] is Map
      ? Map<String, dynamic>.from(a[at + 2] as Map)
      : const <String, dynamic>{};
  return Target(
    kind,
    a[at + 1] as String,
    sel: (opts['sel'] ?? 'first') as String,
    within: opts['in'] as String?,
    grow: opts['grow'] as String?,
    up: (opts['up'] as num?)?.toInt() ?? 0,
    opt: opts['opt'] == true,
  );
}
