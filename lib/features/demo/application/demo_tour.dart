import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:barbershop_app/core/config/env.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/router/app_router.dart';
import 'package:barbershop_app/core/utils/shop_time.dart';
import 'package:barbershop_app/features/customers/data/customers_repository.dart';
import 'package:barbershop_app/features/demo/application/tour_script.dart';
import 'package:barbershop_app/features/demo/application/ui_driver.dart';
import 'package:barbershop_app/features/lock/application/biometric_setup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show GlobalKey, PopupRoute, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// What the tour overlay draws right now.
@immutable
class DemoStage {
  const DemoStage({
    this.active = false,
    this.countdown,
    this.ring,
    this.dot,
    this.pressing = false,
    this.caption,
    this.captionOnTop = false,
    this.captionsOn = true,
  });

  /// The tour is running (also during the countdown).
  final bool active;

  /// 3, 2, 1 before it starts.
  final int? countdown;

  /// The control being talked about (global logical px).
  final Rect? ring;

  /// The "finger": where it touches the screen.
  final Offset? dot;
  final bool pressing;
  final String? caption;
  final bool captionOnTop;
  final bool captionsOn;

  DemoStage copyWith({
    bool? active,
    Object? countdown = _keep,
    Object? ring = _keep,
    Object? dot = _keep,
    bool? pressing,
    Object? caption = _keep,
    bool? captionOnTop,
    bool? captionsOn,
  }) => DemoStage(
    active: active ?? this.active,
    countdown: identical(countdown, _keep) ? this.countdown : countdown as int?,
    ring: identical(ring, _keep) ? this.ring : ring as Rect?,
    dot: identical(dot, _keep) ? this.dot : dot as Offset?,
    pressing: pressing ?? this.pressing,
    caption: identical(caption, _keep) ? this.caption : caption as String?,
    captionOnTop: captionOnTop ?? this.captionOnTop,
    captionsOn: captionsOn ?? this.captionsOn,
  );

  static const _keep = Object();
}

/// Where the tour's own audio files are (`tool/demo/make_audio.mjs` makes them).
const _audioDir = 'demo/audio';

/// Developer switches (dart-define), all off in a normal build:
/// TOUR_AUTOSTART starts the tour by itself after sign-in; TOUR_FAST skips the voice
/// and shortens the pauses (the whole flow in a few minutes); TOUR_SHOTS saves a
/// picture after every action; TOUR_CHAPTER runs one chapter; TOUR_FROM / TOUR_TO
/// run only a range of beats.
const bool kTourAutostart = bool.fromEnvironment('TOUR_AUTOSTART');
const bool kTourFast = bool.fromEnvironment('TOUR_FAST');

/// Voice speed and pause scale for the real tour (1.0 = original pace).
const double kTourVoiceRate = 1.18;
const double kTourPauseScale = 0.7;
const bool kTourShots = bool.fromEnvironment('TOUR_SHOTS');
const String kTourChapter = String.fromEnvironment('TOUR_CHAPTER');
const String kTourFrom = String.fromEnvironment('TOUR_FROM');
const String kTourTo = String.fromEnvironment('TOUR_TO');

/// Wraps the whole app (overlay included) so a picture of the screen can be taken.
final GlobalKey tourBoundaryKey = GlobalKey();

/// Where the pictures go (readable with adb pull). A `tour.json` placed next to this
/// folder replaces the bundled script in test builds (no rebuild to try a change).
const _filesDir =
    '/storage/emulated/0/Android/data/ca.rosenthalbarbershop.app/files';
const _shotsDir = '$_filesDir/tour';

class _Voice {
  _Voice(this.done, this.ms);

  /// Completes when the voice has finished.
  final Future<void> done;

  /// How long it speaks (what a `sweep` spreads its rings over).
  final int ms;
}

/// Plays the narrated demo tour by itself: moves through the real screens,
/// presses real buttons, types into real fields and saves real data, with a
/// voice explaining each step. Nothing is dimmed or blurred: the app stays fully
/// visible, with a thin ring, a finger dot and a small subtitle on top.
///
/// The script is chapters of beats. One beat = one spoken sentence, and what the
/// screen does is timed to that sentence: first the silent `pre` actions (scroll to
/// the thing, open the screen), then the voice starts and the `do` actions run while
/// it speaks, and the beat ends when both are done.
class DemoTour extends Notifier<DemoStage> {
  final UiDriver _driver = UiDriver();
  bool _stop = false;
  bool _running = false;

  /// Steps that did not work (listed in the log after the tour).
  final List<String> problems = [];

  @override
  DemoStage build() => const DemoStage();

  bool get running => _running;

  Future<List<TourChapter>> _load() async {
    String? raw;
    if (!Env.isProd) {
      final f = File('$_filesDir/tour.json');
      if (f.existsSync()) {
        raw = f.readAsStringSync();
        debugPrint('[tour] script: the file on the phone');
      }
    }
    raw ??= await rootBundle.loadString('assets/demo/tour.json');
    final list = (jsonDecode(raw) as Map<String, dynamic>)['chapters'] as List;
    return [
      for (final c in list)
        TourChapter.fromJson(Map<String, dynamic>.from(c as Map)),
    ];
  }

  /// The chapters of the script (for the list the tour is started from).
  Future<List<TourChapter>> chapters() => _load();

  void stop() {
    _stop = true;
  }

  /// The demo customer the tour creates (see docs/DEMO_TOUR_SCRIPT.md).
  static const demoPhone = '7805550777';

  /// Before anything is touched: is the server there, and is the demo data clean?
  /// Returns a plain sentence for what is wrong, or null.
  Future<String?> _preflight(List<TourChapter> chapters) async {
    try {
      await ref.read(apiClientProvider).get('/health');
    } catch (_) {
      return 'The shop server does not answer. Start Laragon (Apache and MySQL) and try again.';
    }
    final creates = chapters.any(
      (c) => c.beats.any(
        (b) => [...b.pre, ...b.actions].any(
          (a) => a.first == 'type' && a.length > 2 && a[2] == 'Olivia Tremblay',
        ),
      ),
    );
    if (creates) {
      try {
        final found = await ref
            .read(customersRepositoryProvider)
            .list(q: demoPhone);
        if (found.items.isNotEmpty) {
          return 'The demo customer already exists. Run tool/demo/restore.sh first.';
        }
      } catch (_) {
        // The customers list not answering is the server problem above.
      }
    }
    return null;
  }

  /// A keyboard must never cover the screen while it is recorded.
  Timer? _keyboardGuard;

  void _guardKeyboard() {
    _keyboardGuard?.cancel();
    _keyboardGuard = Timer.periodic(const Duration(milliseconds: 350), (_) {
      final view = WidgetsBinding.instance.platformDispatcher.implicitView;
      if (view != null && view.viewInsets.bottom > 0) {
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
        );
      }
    });
  }

  /// Runs the whole tour (or the chapter / beats the test switches ask for).
  Future<void> start({List<TourChapter>? chapters}) async {
    if (_running) return;
    _running = true;
    _stop = false;
    problems.clear();
    ref.read(biometricOfferProvider.notifier).dismiss();
    try {
      await WakelockPlus.enable(); // a long recording must not sleep
    } catch (_) {}
    _guardKeyboard();
    state = state.copyWith(
      active: true,
      countdown: null,
      caption: null,
      ring: null,
    );
    try {
      var list = chapters ?? await _load();
      if (kTourChapter.isNotEmpty) {
        list = [
          for (final c in list)
            if (c.id == kTourChapter) c,
        ];
      }
      final trouble = await _preflight(list);
      if (trouble != null) {
        debugPrint('[tour] PREFLIGHT FAIL $trouble');
        problems.add('preflight: $trouble');
        state = state.copyWith(caption: trouble, captionOnTop: true);
        await _wait(6000);
        return;
      }
      for (var n = 3; n >= 1 && !_stop; n--) {
        state = state.copyWith(countdown: n);
        await _wait(1000);
      }
      state = state.copyWith(countdown: null);
      for (final c in list) {
        if (_stop) break;
        await _chapter(c);
      }
      if (!_stop) {
        // So the end is never mistaken for a tour that broke.
        state = state.copyWith(
          caption: 'End of the tour. More chapters are being added.',
          captionOnTop: false,
          ring: null,
        );
        await _wait(3500);
      }
    } finally {
      _keyboardGuard?.cancel();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      state = state.copyWith(
        active: false,
        countdown: null,
        ring: null,
        dot: null,
        caption: null,
      );
      _running = false;
      for (final p in problems) {
        debugPrint('[tour] problem: $p');
      }
      debugPrint('[tour] finished, ${problems.length} problem(s)');
    }
  }

  // ---------------------------------------------------------------- one chapter

  /// Closes any sheet or dialog that is still open.
  void _closeSheets() {
    final nav = ref.read(appRouterProvider).routerDelegate.navigatorKey;
    nav.currentState?.popUntil((r) => r is! PopupRoute);
  }

  Future<void> _chapter(TourChapter c) async {
    debugPrint('[tour] == ${c.id} ${c.name}');
    _closeSheets();
    ref.read(appRouterProvider).go(c.start);
    await _wait(900);
    if (c.ready != null) {
      try {
        await _driver.locate(c.ready!, timeout: const Duration(seconds: 12));
      } on TourStepFailed catch (e) {
        problems.add('${c.id}: the screen did not come up (${e.message})');
        debugPrint('[tour] FAIL chapter ${c.id} did not start: ${e.message}');
        return;
      }
    }
    await _wait(700);
    var beats = c.beats;
    if (kTourFrom.isNotEmpty || kTourTo.isNotEmpty) {
      final from = beats.indexWhere((b) => b.id == kTourFrom);
      final to = beats.indexWhere((b) => b.id == kTourTo);
      beats = beats.sublist(
        from < 0 ? 0 : from,
        to < 0 ? beats.length : to + 1,
      );
    }
    for (final b in beats) {
      if (_stop) break;
      await _beat(b);
    }
  }

  // ---------------------------------------------------------------- one beat

  Future<void> _beat(TourBeat b) async {
    if (b.ifVisible != null) {
      try {
        await _driver.locate(
          b.ifVisible!,
          timeout: const Duration(milliseconds: 1500),
        );
      } on TourStepFailed {
        debugPrint('[tour] ${b.id} skipped (not on screen today)');
        return;
      }
    }
    debugPrint('[tour] ${b.id}');
    var failed = false;
    var n = 0;

    Future<void> run(List<List<dynamic>> list, int voiceMs) async {
      for (final a in list) {
        if (_stop || failed) break;
        n++;
        final watch = Stopwatch()..start();
        var result = 'ok';
        try {
          // No single step may freeze the tour: after 40 s it is a logged failure.
          await _do(a, voiceMs).timeout(const Duration(seconds: 40));
        } on _Skipped {
          result = 'skipped (optional, not there)';
        } on TourStepFailed catch (e) {
          result = 'FAIL ${e.message}';
          problems.add('${b.id}.$n: ${e.message}');
          failed = true;
        } catch (e) {
          result = 'ERROR $e';
          problems.add('${b.id}.$n: $e');
          failed = true;
        }
        debugPrint(
          '[tour]   ${b.id}.$n ${a.take(3).join(' ')} -> $result (${watch.elapsedMilliseconds}ms)',
        );
        await _shot('${b.id}_$n');
      }
    }

    state = state.copyWith(caption: null);
    await run(b.pre, 0); // silent: go to the thing first
    state = state.copyWith(caption: b.subtitle);
    final voice = await _startVoice(b);
    await run(b.actions, voice.ms); // while the voice speaks
    await voice.done; // never cut the voice off
    await _shot('${b.id}_end');
    await _wait(250);
    state = state.copyWith(ring: null, caption: null);
  }

  /// Starts the voice and tells how long it speaks.
  Future<_Voice> _startVoice(TourBeat b) async {
    final words = b.say.split(RegExp(r'\s+')).length;
    final estimate = (words * 360).clamp(1500, 40000);
    if (kTourFast) return _Voice(_wait(estimate ~/ 3), estimate ~/ 3);
    final player = AudioPlayer();
    try {
      await player
          .setSource(AssetSource('$_audioDir/${b.id}.mp3'))
          .timeout(const Duration(seconds: 6));
      await player.setPlaybackRate(kTourVoiceRate);
      final raw =
          await player.getDuration() ?? Duration(milliseconds: estimate);
      final length = Duration(
        milliseconds: (raw.inMilliseconds / kTourVoiceRate).round(),
      );
      final done = player.onPlayerComplete.first.timeout(
        length + const Duration(seconds: 6),
      );
      await player.resume().timeout(const Duration(seconds: 6));
      debugPrint('[tour]   voice ${b.id} ${length.inMilliseconds}ms');
      return _Voice(
        done
            .then<void>((_) {})
            .catchError((Object _) {})
            .whenComplete(() => unawaited(player.dispose())),
        length.inMilliseconds,
      );
    } catch (e) {
      problems.add('${b.id}: voice ($e)');
      debugPrint('[tour]   voice ${b.id} FAILED: $e');
      unawaited(player.dispose());
      return _Voice(_wait(estimate), estimate);
    }
  }

  // ---------------------------------------------------------------- actions

  Future<void> _do(List<dynamic> a, int voiceMs) async {
    switch (a.first as String) {
      case 'pause':
        await _wait(a[1] as int);
      case 'go':
        ref.read(appRouterProvider).go(a[1] as String);
        await _wait(800);
      case 'closeSheet':
        _closeSheets();
        await _wait(500);
      case 'scroll':
        await _driver.scrollBy((a[1] as num).toDouble(), a[2] as int);
      case 'scrollTo':
        final t = parseTarget(a, 1);
        try {
          await _driver.scrollTo(t);
        } on TourStepFailed {
          if (t.opt) throw const _Skipped();
          rethrow;
        }
      case 'ring':
        final t = parseTarget(a, 1);
        final f = await _find(t);
        _showRing(_driver.grown(f, t));
        await _wait(600);
      case 'sweep':
        final items = [
          for (final x in (a[1] as List))
            parseTarget(List<dynamic>.from(x as List), 0),
        ];
        final each = (voiceMs ~/ (items.isEmpty ? 1 : items.length)).clamp(
          900,
          4000,
        );
        for (final t in items) {
          try {
            final f = await _find(t);
            _showRing(_driver.grown(f, t));
            await _wait(each);
          } on _Skipped {
            continue;
          }
        }
      case 'tap':
        await _tap(parseTarget(a, 1));
      case 'swipe':
        await _swipe(Map<String, dynamic>.from(a[1] as Map));
      case 'pull':
        // A real finger pulls the page down and holds it until it refreshes.
        final s = _screenSize();
        await _drag(
          Offset(s.width * 0.5, s.height * 0.30),
          const Offset(0, 300),
          800,
          hold: 700,
        );
        await _wait(1500);
      case 'nav':
        await _nav(a[1] as String);
      case 'back':
        const back = Target(
          MatchKind.icon,
          'arrow_back_rounded',
          sel: 'highest',
          grow: 'tap',
        );
        if (_driver.isVisible(back)) await _tap(back);
      case 'clear':
        final f = await _driver.locate(Target(MatchKind.hint, a[1] as String));
        _showRing(f.rect.inflate(6));
        _driver.clear(f);
        await _wait(500);
      case 'tapAt':
        // A press on an empty spot (closes a small menu); (0..1, 0..1) of the screen.
        final s = _screenSize();
        await _press(Offset(s.width * (a[1] as num), s.height * (a[2] as num)));
      case 'pinch':
        final m = Map<String, dynamic>.from(a[1] as Map);
        final sz = _screenSize();
        final at = m['at'] as List;
        final c = Offset(
          sz.width * (at[0] as num).toDouble(),
          sz.height * (at[1] as num).toDouble(),
        );
        state = state.copyWith(dot: c, pressing: true);
        await _wait(300);
        await _driver.pinch(
          c,
          (m['from'] as num).toDouble(),
          (m['to'] as num).toDouble(),
          (m['ms'] as num?)?.toInt() ?? 900,
          onMove: (p) => state = state.copyWith(dot: p, pressing: true),
        );
        state = state.copyWith(pressing: false);
        await _wait(500);
        state = state.copyWith(dot: null);
      case 'doubleTap':
        final sz2 = _screenSize();
        final p2 = Offset(
          sz2.width * (a[1] as num).toDouble(),
          sz2.height * (a[2] as num).toDouble(),
        );
        state = state.copyWith(dot: p2, pressing: false);
        await _wait(400);
        state = state.copyWith(pressing: true);
        await _driver.tapAt(p2);
        await Future<void>.delayed(const Duration(milliseconds: 110));
        await _driver.tapAt(p2);
        await _wait(300);
        state = state.copyWith(pressing: false);
        await _wait(500);
        state = state.copyWith(dot: null);
      case 'pickSlot':
        await _pickSlot([for (final d in (a[1] as List)) d as String]);
      case 'type':
        final f = await _driver.locate(Target(MatchKind.hint, a[1] as String));
        _showRing(f.rect.inflate(6));
        await _driver.type(f, a[2] as String);
        await _wait(350);
      default:
        throw TourStepFailed('unknown action ${a.first}');
    }
  }

  /// Finds [t]; an optional target that is not there is skipped, not failed.
  /// A required one that is not on screen is looked for further down (and up) the
  /// page, so a long page never hides it.
  Future<Found> _find(Target t) async {
    try {
      return await _driver.locate(
        t,
        timeout: Duration(milliseconds: t.opt ? 2000 : 1200),
      );
    } on TourStepFailed {
      if (t.opt) throw const _Skipped();
    }
    return _driver.scrollTo(t);
  }

  static const _navIcons = {
    'home': 'home_outlined|home_rounded',
    'appointments': 'event_note_outlined|event_note_rounded',
    'calendar': 'calendar_month_outlined|calendar_month_rounded',
    'more': 'menu_rounded',
    'plus': 'add_rounded',
  };

  Future<void> _nav(String name) async {
    final v = _navIcons[name];
    if (v == null) throw TourStepFailed('unknown nav item $name');
    await _tap(Target(MatchKind.icon, v, sel: 'lowest', grow: 'tap'));
  }

  Size _screenSize() {
    final v = WidgetsBinding.instance.platformDispatcher.implicitView;
    return v == null
        ? const Size(360, 800)
        : v.physicalSize / v.devicePixelRatio;
  }

  Future<void> _tap(Target t) async {
    final f = await _find(t);
    // Point at the whole control, then press where the words are.
    final t2 = t.grow == null
        ? Target(
            t.kind,
            t.value,
            sel: t.sel,
            within: t.within,
            grow: 'tap',
            up: t.up,
            opt: t.opt,
          )
        : t;
    _showRing(_driver.grown(f, t2));
    await _wait(450);
    // Measure again: the thing may have settled or moved while we looked at it.
    final again = await _find(t);
    debugPrint('[tour]   tap $t');
    await _press(again.center);
  }

  /// The finger moves to [p], presses, and fades.
  Future<void> _press(Offset p) async {
    state = state.copyWith(dot: p, pressing: false);
    await _wait(420);
    state = state.copyWith(pressing: true);
    debugPrint('[tour]   press at ${p.dx.round()},${p.dy.round()}');
    await _driver.tapAt(p);
    await _wait(180);
    state = state.copyWith(pressing: false);
    await _wait(550);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (state.dot == p) state = state.copyWith(dot: null);
      }),
    );
  }

  /// "{d3}" is the day of the month three days from today (shop time).
  String _day(String s) {
    final m = RegExp(r'^\{d(\d+)\}$').firstMatch(s);
    if (m == null) return s;
    final d = ShopTime.today().add(Duration(days: int.parse(m.group(1)!)));
    return '${d.day}';
  }

  /// Picks a day and one of its free times. Tries the listed days in turn: a day
  /// that is closed, or already full, has no times, so the next one is used.
  Future<void> _pickSlot(List<String> days) async {
    const slot = Target(
      MatchKind.regex,
      r'^\d{1,2}:\d{2}\s?(AM|PM)$',
      grow: 'tap',
    );
    for (final d in days) {
      await _tap(
        Target(MatchKind.text, _day(d), within: 'DateStrip', grow: 'tap'),
      );
      await _wait(1800); // the free times load
      try {
        await _driver.locate(slot, timeout: const Duration(seconds: 3));
      } on TourStepFailed {
        continue; // no free time that day
      }
      await _tap(slot);
      return;
    }
    throw const TourStepFailed('no free time on any of the days tried');
  }

  /// {"at": target or [fx, fy], "dx": -240, "dy": 0, "ms": 900}
  Future<void> _swipe(Map<String, dynamic> m) async {
    final at = m['at'];
    final Offset from;
    if (at is List && at.isNotEmpty && at.first is String) {
      final t = parseTarget(List<dynamic>.from(at), 0);
      final f = await _find(t);
      from = f.center;
    } else if (at is List) {
      final s = _screenSize();
      from = Offset(
        s.width * (at[0] as num).toDouble(),
        s.height * (at[1] as num).toDouble(),
      );
    } else {
      throw const TourStepFailed('swipe needs "at"');
    }
    await _drag(
      from,
      Offset(
        (m['dx'] as num? ?? 0).toDouble(),
        (m['dy'] as num? ?? 0).toDouble(),
      ),
      (m['ms'] as num?)?.toInt() ?? 900,
    );
  }

  Future<void> _drag(
    Offset from,
    Offset delta,
    int ms, {
    int hold = 160,
  }) async {
    state = state.copyWith(dot: from, pressing: true);
    await _wait(250);
    await _driver.swipe(
      from,
      delta,
      ms,
      holdMs: hold,
      onMove: (p) => state = state.copyWith(dot: p, pressing: true),
    );
    state = state.copyWith(pressing: false);
    await _wait(300);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        state = state.copyWith(dot: null);
      }),
    );
  }

  void _showRing(Rect r) {
    state = state.copyWith(
      ring: r,
      captionOnTop: r.center.dy > _screenSize().height * 0.55,
    );
  }

  /// Pauses are shortened in fast mode; real timing otherwise.
  Future<void> _wait(int ms) => Future<void>.delayed(
    Duration(
      milliseconds: kTourFast
          ? (ms * 0.4).round()
          : (ms * kTourPauseScale).round(),
    ),
  );

  /// Saves a picture of the screen (ring, finger and subtitle included) when
  /// TOUR_SHOTS is on, so a run can be checked frame by frame.
  Future<void> _shot(String name) async {
    if (!kTourShots) return;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final b = tourBoundaryKey.currentContext?.findRenderObject();
      if (b is! RenderRepaintBoundary) return;
      final image = await b.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      Directory(_shotsDir).createSync(recursive: true);
      File('$_shotsDir/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
    } catch (e) {
      debugPrint('[tour] shot failed: $e');
    }
  }
}

/// An optional target is not on screen today: the step is skipped, not failed.
class _Skipped implements Exception {
  const _Skipped();
}

final demoTourProvider = NotifierProvider<DemoTour, DemoStage>(DemoTour.new);

/// True while the tour runs (the app lock and the fingerprint offer stay out of
/// its way).
final demoActiveProvider = Provider<bool>(
  (ref) => ref.watch(demoTourProvider.select((s) => s.active)),
);
