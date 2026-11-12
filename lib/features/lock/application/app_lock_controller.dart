import 'dart:async';

import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/security/biometric_vault.dart';
import 'package:barbershop_app/features/auth/application/session_controller.dart';
import 'package:barbershop_app/features/demo/application/demo_tour.dart';
import 'package:barbershop_app/features/lock/application/biometric_setup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show FocusManager;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the lock layer shows right now.
@immutable
class AppLockState {
  const AppLockState({
    this.locked = false,
    this.covered = false,
    this.prompting = false,
    this.failures = 0,
    this.message,
  });

  /// The app is hidden behind the unlock panel (while it is open and running).
  final bool locked;

  /// The app is leaving the screen: a brand cover replaces the content so the
  /// Recents thumbnail shows nothing private.
  final bool covered;

  /// The phone's prompt is open.
  final bool prompting;

  /// Unlock tries that did not work since the panel appeared.
  final int failures;

  /// A calm sentence for the panel (null = nothing to say).
  final String? message;

  /// After this many misses the password is offered as the main way.
  static const troubleAfter = 3;

  bool get inTrouble => failures >= troubleAfter;

  AppLockState copyWith({
    bool? locked,
    bool? covered,
    bool? prompting,
    int? failures,
    String? message,
    bool clearMessage = false,
  }) => AppLockState(
    locked: locked ?? this.locked,
    covered: covered ?? this.covered,
    prompting: prompting ?? this.prompting,
    failures: failures ?? this.failures,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// Locks the running app after the chosen time away or idle, covers it while it
/// leaves the screen, and runs the unlock prompt (for the open app and for a
/// session that is locked at launch).
///
/// Only when the session is signed in and protected: with the feature off none
/// of this does anything.
class AppLockController extends Notifier<AppLockState> {
  /// Replaced in tests.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// Replaced in tests (a timer that fires when the test says so).
  @visibleForTesting
  Timer Function(Duration, void Function()) timerFactory = Timer.new;

  DateTime? _leftAt;
  DateTime? _lastTouch;
  Timer? _idle;

  @override
  AppLockState build() {
    ref.onDispose(() => _idle?.cancel());
    // A different session (sign in, sign out, launch lock) starts clean.
    ref.listen(sessionControllerProvider, (previous, next) {
      if (next is! SignedIn) {
        _idle?.cancel();
        _leftAt = null;
        state = const AppLockState();
      } else if (previous is! SignedIn) {
        _armIdle();
      }
    });
    return const AppLockState();
  }

  /// The narrated demo tour keeps the lock out of its way.
  bool get _active =>
      ref.read(sessionControllerProvider) is SignedIn &&
      ref.read(tokenStoreProvider).isProtected &&
      !ref.read(demoActiveProvider);

  Duration get _timeout => ref.read(lockTimeoutProvider).duration;

  // ---- lifecycle (wired in app.dart)

  /// The window is losing focus (also happens while the phone's prompt is open).
  void onInactive() {
    if (_active && !state.locked && !state.covered) {
      state = state.copyWith(covered: true);
    }
  }

  /// The app left the screen for real.
  void onPaused() {
    if (!_active || state.locked || state.prompting) return;
    _leftAt = clock();
    _idle?.cancel();
  }

  /// The app is back in front.
  void onResumed() {
    if (state.covered) state = state.copyWith(covered: false);
    if (!_active || state.locked || state.prompting) return;
    final left = _leftAt;
    _leftAt = null;
    if (left != null) {
      final away = clock().difference(left);
      // A clock set back is treated as "long ago": never a way round the lock.
      if (away.isNegative || away >= _timeout) {
        lock();
        return;
      }
    }
    _armIdle();
  }

  // ---- inactivity while the app is open

  /// Any touch: the person is there. (Called for every pointer-down; cheap.)
  void touch() {
    if (!_active || state.locked) return;
    final now = clock();
    final last = _lastTouch;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastTouch = now;
    _armIdle();
  }

  void _armIdle() {
    _idle?.cancel();
    final t = _timeout;
    // "Immediately" locks when the app is left, not while it is in use.
    if (t == Duration.zero || !_active || state.locked) return;
    _idle = timerFactory(t, lock);
  }

  /// Re-arm after the person changed the time in Settings.
  void timeoutChanged() => _armIdle();

  // ---- lock / unlock

  void lock() {
    if (!_active || state.locked) return;
    _idle?.cancel();
    // A keyboard left open would hover over the unlock panel.
    FocusManager.instance.primaryFocus?.unfocus();
    state = state.copyWith(
      locked: true,
      covered: false,
      failures: 0,
      clearMessage: true,
    );
  }

  /// Opens the phone's prompt. Safe to call twice (the second is ignored).
  Future<void> unlock() async {
    if (state.prompting) return;
    state = state.copyWith(prompting: true, clearMessage: true);
    final session = ref.read(sessionControllerProvider.notifier);
    final atLaunch = ref.read(sessionControllerProvider) is SessionLocked;

    final VaultFailure? failure = atLaunch
        ? await session.unlockSaved()
        : await session.reauthenticate();

    if (failure == null) {
      state = const AppLockState();
      _lastTouch = null;
      _armIdle();
      return;
    }
    if (ref.read(sessionControllerProvider) is SignedOut) {
      return; // the key was gone: the session ended, the sign-in screen explains
    }
    state = state.copyWith(
      prompting: false,
      failures: state.failures + 1,
      message: _words(failure),
    );
  }

  /// A calm sentence, or null when saying nothing is kinder (the person
  /// closed the prompt themselves).
  static String? _words(VaultFailure f) => switch (f) {
    VaultFailure.cancelled => null,
    VaultFailure.lockedOut =>
      'Too many tries. Wait a moment, or use your password.',
    _ => 'That did not work. Try again, or use your password.',
  };

  /// "Use password instead": signs this phone out.
  Future<void> usePassword() async {
    final session = ref.read(sessionControllerProvider.notifier);
    if (ref.read(sessionControllerProvider) is SessionLocked) {
      await session.signOutLocked();
    } else {
      await session.signOut();
    }
  }
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);
