import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Dev tool: with `--dart-define=FRAME_LOG=true` the app prints, every 120
/// frames, how many were slow (build or raster over 16 ms, the 60 fps budget)
/// and the worst ones. Read it with `adb logcat -s flutter`. Off in normal builds.
class FrameLog {
  static const enabled = bool.fromEnvironment('FRAME_LOG');

  static final _build = <int>[];
  static final _raster = <int>[];

  static void start() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _build.add(t.buildDuration.inMicroseconds);
      _raster.add(t.rasterDuration.inMicroseconds);
    }
    if (_build.length < 120) return;
    int slow(List<int> v, int limit) => v.where((x) => x > limit).length;
    int worst(List<int> v) => v.reduce((a, b) => a > b ? a : b);
    int p(List<int> v, double q) {
      final s = [...v]..sort();
      return s[(s.length * q).floor().clamp(0, s.length - 1)];
    }

    String ms(int us) => (us / 1000).toStringAsFixed(1);
    debugPrint(
      '[frames] n=${_build.length} '
      'build p50=${ms(p(_build, .5))} p90=${ms(p(_build, .9))} max=${ms(worst(_build))} slow=${slow(_build, 16000)} | '
      'raster p50=${ms(p(_raster, .5))} p90=${ms(p(_raster, .9))} max=${ms(worst(_raster))} slow=${slow(_raster, 16000)}',
    );
    _build.clear();
    _raster.clear();
  }
}
