import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// How a control on the screen is recognised.
enum MatchKind { text, textStarts, regex, icon, hint, label }

/// "The thing to point at": by its words, its icon or its placeholder, optionally
/// only inside a given kind of widget, which of several matches to take, and how
/// far to grow the outline from the words to the control or card around them.
class Target {
  const Target(
    this.kind,
    this.value, {
    this.sel = 'first',
    this.within,
    this.grow,
    this.up = 0,
    this.opt = false,
  });

  final MatchKind kind;
  final String value;

  /// `first`, `last` (the one in front), `lowest` or `highest` on the screen.
  final String sel;

  /// Only inside an ancestor widget of this runtimeType name (e.g. `DateStrip`).
  final String? within;

  /// `tap` (the nearest thing a finger can press around it) or `card` (the nearest
  /// rounded card or row around it). Null: the words themselves.
  final String? grow;

  /// With `grow`: skip this many matches outward (1 = the next card out).
  final int up;

  /// Optional: when it is not on screen the step is skipped, not failed.
  final bool opt;

  @override
  String toString() => '${kind.name}:$value';
}

/// A control found on screen: its element and where it is (global, logical px).
class Found {
  Found(this.element, this.rect);

  final Element element;
  final Rect rect;

  Offset get center => rect.center;
}

class TourStepFailed implements Exception {
  const TourStepFailed(this.message);

  final String message;

  @override
  String toString() => 'TourStepFailed: $message';
}

/// Icons the tour may name (the script is JSON, so icons are named by string).
const Map<String, IconData> tourIcons = {
  'home_outlined': Icons.home_outlined,
  'home_rounded': Icons.home_rounded,
  'event_note_outlined': Icons.event_note_outlined,
  'event_note_rounded': Icons.event_note_rounded,
  'calendar_month_outlined': Icons.calendar_month_outlined,
  'calendar_month_rounded': Icons.calendar_month_rounded,
  'menu_rounded': Icons.menu_rounded,
  'add_rounded': Icons.add_rounded,
  'person_add_alt_1_rounded': Icons.person_add_alt_1_rounded,
  'zoom_in_rounded': Icons.zoom_in_rounded,
  'search_rounded': Icons.search_rounded,
  'tune_rounded': Icons.tune_rounded,
  'arrow_back_rounded': Icons.arrow_back_rounded,
  'groups_rounded': Icons.groups_rounded,
  'call_rounded': Icons.call_rounded,
  'check_rounded': Icons.check_rounded,
  'coffee_rounded': Icons.coffee_rounded,
  'fullscreen_rounded': Icons.fullscreen_rounded,
  'more_vert_rounded': Icons.more_vert_rounded,
  'copy_rounded': Icons.copy_rounded,
  'sms_rounded': Icons.sms_rounded,
  'content_cut_rounded': Icons.content_cut_rounded,
  'schedule_rounded': Icons.schedule_rounded,
  'close_rounded': Icons.close_rounded,
  'edit_rounded': Icons.edit_rounded,
  'drag_handle_rounded': Icons.drag_handle_rounded,
  'add_circle_rounded': Icons.add_circle_rounded,
  'chevron_left_rounded': Icons.chevron_left_rounded,
  'chevron_right_rounded': Icons.chevron_right_rounded,
  'zoom_out_map_rounded': Icons.zoom_out_map_rounded,
  'zoom_in_map_rounded': Icons.zoom_in_map_rounded,
  'expand_more_rounded': Icons.expand_more_rounded,
  'help_outline_rounded': Icons.help_outline_rounded,
};

/// Does what a person does with a finger, on the real running app: finds a
/// control by its words or icon, scrolls until it is on screen, points at the
/// whole control, presses it with real touch events, drags, and types.
/// Used by the demo tour only.
///
/// Everything is found by looking at what is really on screen and what a touch
/// would really hit, so a control hidden behind a sheet or on another tab is
/// never "found".
class UiDriver {
  int _pointer = 90000;

  // ---------------------------------------------------------------- finding

  static bool _eq(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  bool _matches(Widget w, Target t) {
    switch (t.kind) {
      case MatchKind.text:
        return w is Text && _eq(_textOf(w), t.value);
      case MatchKind.textStarts:
        return w is Text &&
            _textOf(w).trim().toLowerCase().startsWith(t.value.toLowerCase());
      case MatchKind.regex:
        return w is Text && RegExp(t.value).hasMatch(_textOf(w).trim());
      case MatchKind.icon:
        // "home_outlined|home_rounded": any of several (a selected tab has another icon).
        return w is Icon &&
            t.value.split('|').any((n) => w.icon == tourIcons[n.trim()]);
      case MatchKind.hint:
        return w is TextField && w.decoration?.hintText == t.value;
      case MatchKind.label:
        return w is Semantics && _eq(w.properties.label ?? '', t.value);
    }
  }

  static String _textOf(Text w) => w.data ?? w.textSpan?.toPlainText() ?? '';

  static bool _hasAncestor(Element e, String type) {
    var found = false;
    e.visitAncestorElements((a) {
      if (a.widget.runtimeType.toString() == type) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  /// Every element matching [t] (visible or not), in tree order.
  List<Element> _candidates(Target t) {
    final out = <Element>[];
    void visit(Element e) {
      if (_matches(e.widget, t) &&
          (t.within == null || _hasAncestor(e, t.within!))) {
        out.add(e);
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return out;
  }

  Size get _screen {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    return view == null
        ? const Size(360, 800)
        : view.physicalSize / view.devicePixelRatio;
  }

  /// Where [e] is on screen if a finger at its centre would really touch it.
  Found? _visible(Element e) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return null;
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final rect = (ro.localToGlobal(Offset.zero) & ro.size).intersect(screen);
    if (rect.width < 4 || rect.height < 4) return null;
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(result, rect.center, view.viewId);
    final reachable = result.path.any((entry) => identical(entry.target, ro));
    return reachable ? Found(e, ro.localToGlobal(Offset.zero) & ro.size) : null;
  }

  Found? _pick(List<Found> list, String sel) {
    if (list.isEmpty) return null;
    return switch (sel) {
      'last' => list.last,
      'lowest' => list.reduce((a, b) => a.center.dy >= b.center.dy ? a : b),
      'highest' => list.reduce((a, b) => a.center.dy <= b.center.dy ? a : b),
      _ => list.first,
    };
  }

  /// A quick look: is [t] on screen right now?
  bool isVisible(Target t) =>
      _pick([for (final e in _candidates(t)) ?_visible(e)], t.sel) != null;

  /// The control or card around [f] as a person sees it (see [Target.grow]).
  /// Falls back to the words themselves with some air around them.
  Rect grown(Found f, Target t) {
    final mode = t.grow;
    if (mode == null) return f.rect;
    final screen = _screen;
    var skip = t.up;
    Rect? result;
    f.element.visitAncestorElements((a) {
      final ro = a.renderObject;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) return true;
      final r = ro.localToGlobal(Offset.zero) & ro.size;
      // Never climb out to the whole page.
      if (r.width > screen.width * 1.02 || r.height > screen.height * 0.7) {
        return false;
      }
      final w = a.widget;
      var hit = false;
      if (mode == 'tap') {
        hit =
            (w is GestureDetector &&
                (w.onTap != null ||
                    w.onTapUp != null ||
                    w.onLongPress != null)) ||
            w is InkResponse ||
            w is ButtonStyleButton;
      } else if (mode == 'card') {
        if (ro is RenderDecoratedBox) {
          final d = ro.decoration;
          hit =
              d is BoxDecoration &&
              d.borderRadius != null &&
              (d.border != null || d.color != null || d.gradient != null) &&
              r.width >= f.rect.width + 8 &&
              r.height >= f.rect.height + 8 &&
              r.height >= 36;
        }
      }
      if (hit && r.width >= f.rect.width && r.height >= f.rect.height) {
        if (skip == 0) {
          result = r;
          return false;
        }
        skip--;
      }
      return true;
    });
    return (result ?? f.rect.inflate(6)).intersect(Offset.zero & screen);
  }

  /// Waits (up to [timeout]) for [t] to be on screen, scrolling to it if it
  /// exists further down.
  Future<Found> locate(
    Target t, {
    Duration timeout = const Duration(seconds: 7),
  }) async {
    final end = DateTime.now().add(timeout);
    var scrolled = false;
    while (DateTime.now().isBefore(end)) {
      final all = _candidates(t);
      final visible = [for (final e in all) ?_visible(e)];
      final hit = _pick(visible, t.sel);
      if (hit != null) return hit;
      if (all.isNotEmpty && !scrolled) {
        scrolled = true;
        try {
          // Bounded: a scroll that never settles must not freeze the tour.
          await Scrollable.ensureVisible(
            all.first,
            alignment: 0.4,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
          ).timeout(const Duration(seconds: 3));
        } catch (_) {
          // Not inside a scroll view: nothing to scroll.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 180));
    }
    throw TourStepFailed('not found on screen: $t');
  }

  /// Finds [t] even when it is far down a long list that has not built it yet:
  /// scrolls the main list in steps (down, then once from the top) until the
  /// control is built, then brings it to a comfortable height on the screen.
  Future<Found> scrollTo(
    Target t, {
    double align = 0.35,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final end = DateTime.now().add(timeout);
    final h = _screen.height;
    var wentToTop = false;
    var adjusts = 0;
    while (DateTime.now().isBefore(end)) {
      final all = _candidates(t);
      final hit = _pick([for (final e in all) ?_visible(e)], t.sel);
      if (hit != null) {
        final y = hit.center.dy;
        final comfortable = y > h * 0.14 && y < h * 0.66;
        if (comfortable || adjusts >= 4) return hit;
        adjusts++;
        final moved = await scrollBy(y - h * align, 650);
        await Future<void>.delayed(const Duration(milliseconds: 160));
        if (moved.abs() < 2) return hit; // at the end of the list: good enough
        continue;
      }
      if (all.isNotEmpty) {
        try {
          await Scrollable.ensureVisible(
            all.first,
            alignment: align,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
          ).timeout(const Duration(seconds: 3));
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 160));
        continue;
      }
      final moved = await scrollBy(h * 0.62, 600);
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (moved.abs() < 2) {
        if (wentToTop) break;
        wentToTop = true;
        await scrollBy(-100000, 500);
      }
    }
    throw TourStepFailed('not found, even after scrolling: $t');
  }

  // ---------------------------------------------------------------- acting

  /// A real touch: pointer down, a short press, pointer up.
  Future<void> tapAt(Offset p) async {
    final id = _pointer++;
    final binding = GestureBinding.instance;
    binding.handlePointerEvent(
      PointerAddedEvent(
        position: p,
        pointer: id,
        kind: PointerDeviceKind.touch,
      ),
    );
    binding.handlePointerEvent(
      PointerDownEvent(position: p, pointer: id, kind: PointerDeviceKind.touch),
    );
    await Future<void>.delayed(const Duration(milliseconds: 90));
    binding.handlePointerEvent(
      PointerUpEvent(position: p, pointer: id, kind: PointerDeviceKind.touch),
    );
    binding.handlePointerEvent(
      PointerRemovedEvent(
        position: p,
        pointer: id,
        kind: PointerDeviceKind.touch,
      ),
    );
  }

  /// A real finger drag: down at [from], moves by [delta] over [ms] (reporting each
  /// position to [onMove] so the on-screen finger follows), rests [holdMs] and lifts.
  /// A rest before lifting keeps a list from flinging on.
  Future<void> swipe(
    Offset from,
    Offset delta,
    int ms, {
    void Function(Offset p)? onMove,
    int holdMs = 160,
  }) async {
    final id = _pointer++;
    final binding = GestureBinding.instance;
    final clock = Stopwatch()..start();
    Duration now() => Duration(milliseconds: clock.elapsedMilliseconds);
    binding.handlePointerEvent(
      PointerAddedEvent(
        position: from,
        pointer: id,
        kind: PointerDeviceKind.touch,
        timeStamp: now(),
      ),
    );
    binding.handlePointerEvent(
      PointerDownEvent(
        position: from,
        pointer: id,
        kind: PointerDeviceKind.touch,
        timeStamp: now(),
      ),
    );
    onMove?.call(from);
    final steps = (ms / 16).ceil().clamp(2, 400);
    var prev = from;
    for (var i = 1; i <= steps; i++) {
      final p = from + delta * Curves.easeInOut.transform(i / steps);
      binding.handlePointerEvent(
        PointerMoveEvent(
          position: p,
          delta: p - prev,
          pointer: id,
          kind: PointerDeviceKind.touch,
          timeStamp: now(),
        ),
      );
      onMove?.call(p);
      prev = p;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await Future<void>.delayed(Duration(milliseconds: holdMs));
    binding.handlePointerEvent(
      PointerUpEvent(
        position: prev,
        pointer: id,
        kind: PointerDeviceKind.touch,
        timeStamp: now(),
      ),
    );
    binding.handlePointerEvent(
      PointerRemovedEvent(
        position: prev,
        pointer: id,
        kind: PointerDeviceKind.touch,
        timeStamp: now(),
      ),
    );
  }

  /// A real two finger pinch around [center]: the fingers start [from] pixels either side
  /// of it and end [to] pixels either side (bigger = zoom in). [onMove] gets the first
  /// finger so the on-screen finger can follow.
  Future<void> pinch(
    Offset center,
    double from,
    double to,
    int ms, {
    void Function(Offset p)? onMove,
    int holdMs = 200,
  }) async {
    final a = _pointer++;
    final b = _pointer++;
    final binding = GestureBinding.instance;
    final clock = Stopwatch()..start();
    Duration now() => Duration(milliseconds: clock.elapsedMilliseconds);
    Offset pa(double d) => center + Offset(-d, 0);
    Offset pb(double d) => center + Offset(d, 0);
    for (final e in [(a, pa(from)), (b, pb(from))]) {
      binding.handlePointerEvent(
        PointerAddedEvent(
          position: e.$2,
          pointer: e.$1,
          kind: PointerDeviceKind.touch,
          timeStamp: now(),
        ),
      );
      binding.handlePointerEvent(
        PointerDownEvent(
          position: e.$2,
          pointer: e.$1,
          kind: PointerDeviceKind.touch,
          timeStamp: now(),
        ),
      );
    }
    final steps = (ms / 16).ceil().clamp(2, 400);
    var prevA = pa(from);
    var prevB = pb(from);
    for (var i = 1; i <= steps; i++) {
      final d = from + (to - from) * Curves.easeInOut.transform(i / steps);
      final na = pa(d);
      final nb = pb(d);
      binding.handlePointerEvent(
        PointerMoveEvent(
          position: na,
          delta: na - prevA,
          pointer: a,
          kind: PointerDeviceKind.touch,
          timeStamp: now(),
        ),
      );
      binding.handlePointerEvent(
        PointerMoveEvent(
          position: nb,
          delta: nb - prevB,
          pointer: b,
          kind: PointerDeviceKind.touch,
          timeStamp: now(),
        ),
      );
      onMove?.call(na);
      prevA = na;
      prevB = nb;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await Future<void>.delayed(Duration(milliseconds: holdMs));
    for (final e in [(a, prevA), (b, prevB)]) {
      binding.handlePointerEvent(
        PointerUpEvent(
          position: e.$2,
          pointer: e.$1,
          kind: PointerDeviceKind.touch,
          timeStamp: now(),
        ),
      );
      binding.handlePointerEvent(
        PointerRemovedEvent(
          position: e.$2,
          pointer: e.$1,
          kind: PointerDeviceKind.touch,
          timeStamp: now(),
        ),
      );
    }
  }

  /// Types [text] into the field with placeholder [hint], one letter at a time
  /// at a human pace. The keyboard stays closed so the screen stays visible.
  Future<void> type(Found field, String text, {int msPerKey = 70}) async {
    EditableTextState? state;
    void find(Element e) {
      if (state != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        state = e.state as EditableTextState;
        return;
      }
      e.visitChildren(find);
    }

    find(field.element);
    final s = state;
    if (s == null) {
      throw const TourStepFailed('no text field inside the target');
    }
    for (var i = 1; i <= text.length; i++) {
      s.userUpdateTextEditingValue(
        TextEditingValue(
          text: text.substring(0, i),
          selection: TextSelection.collapsed(offset: i),
        ),
        SelectionChangedCause.keyboard,
      );
      await Future<void>.delayed(Duration(milliseconds: msPerKey));
    }
  }

  /// Empties the text field inside [field] (what a person does with the cross or by
  /// deleting the letters).
  void clear(Found field) {
    EditableTextState? state;
    void find(Element e) {
      if (state != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        state = e.state as EditableTextState;
        return;
      }
      e.visitChildren(find);
    }

    find(field.element);
    final s = state;
    if (s == null) {
      throw const TourStepFailed('no text field inside the target');
    }
    s.userUpdateTextEditingValue(
      TextEditingValue.empty,
      SelectionChangedCause.keyboard,
    );
  }

  /// Slides the main scrolling list by [dy] logical pixels over [ms]; returns how
  /// far it really moved (0 at the end of the list).
  Future<double> scrollBy(double dy, int ms) async {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView;
    if (view == null) return 0;
    final screen = view.physicalSize / view.devicePixelRatio;
    ScrollPosition? best;
    var bestArea = 0.0;
    void visit(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        final st = e.state as ScrollableState;
        final pos = st.position;
        final ro = e.renderObject;
        if (pos.axis == Axis.vertical &&
            ro is RenderBox &&
            ro.attached &&
            ro.hasSize &&
            pos.maxScrollExtent > 0) {
          final r = (ro.localToGlobal(Offset.zero) & ro.size).intersect(
            Offset.zero & screen,
          );
          final area = r.width * r.height;
          // The list in front: hit-testable at its centre.
          final result = HitTestResult();
          GestureBinding.instance.hitTestInView(result, r.center, view.viewId);
          if (area > bestArea &&
              result.path.any((x) => identical(x.target, ro))) {
            bestArea = area;
            best = pos;
          }
        }
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    final pos = best;
    if (pos == null) return 0;
    final from = pos.pixels;
    final to = (from + dy).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    if ((to - from).abs() < 1) return 0;
    await pos.animateTo(
      to,
      duration: Duration(milliseconds: ms),
      curve: Curves.easeInOutCubic,
    );
    return pos.pixels - from;
  }
}
