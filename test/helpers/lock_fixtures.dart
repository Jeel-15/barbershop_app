import 'dart:async';

import 'package:barbershop_app/core/security/biometric_capability.dart';

/// A phone with a scripted answer to "what can open the app?".
class FakeCapability implements BiometricCapability {
  FakeCapability(this.answer);

  BiometricKind answer;

  @override
  Future<BiometricKind> kind() async => answer;
}

/// A clock the test moves.
class FakeClock {
  DateTime now = DateTime(2026, 10, 29, 9);

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// A timer that fires only when the test says so.
class ManualTimer implements Timer {
  ManualTimer(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled || fired) return;
    fired = true;
    _callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;
}
