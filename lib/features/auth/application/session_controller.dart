import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/security/biometric_vault.dart';
import 'package:barbershop_app/core/utils/app_version.dart';
import 'package:barbershop_app/features/auth/data/auth_repository.dart';
import 'package:barbershop_app/features/auth/domain/auth_user.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
import 'package:barbershop_app/features/lock/application/biometric_setup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Who is using the app right now.
sealed class SessionState {
  const SessionState();
}

/// Cold start: reading the stored token and asking the server who it belongs to.
class SessionLoading extends SessionState {
  const SessionLoading();
}

class SignedOut extends SessionState {
  const SignedOut({this.message});

  /// Why the user is here when it is not their own doing ("Your session has ended...").
  final String? message;
}

/// A saved session exists but it is locked behind the fingerprint / screen lock.
/// Nothing is loaded (no network call) until the person unlocks it.
class SessionLocked extends SessionState {
  const SessionLocked({this.name, this.roleLabel});

  /// Who the session belongs to, from the saved launch data (for the greeting).
  final String? name;
  final String? roleLabel;
}

class SignedIn extends SessionState {
  const SignedIn(this.bootstrap, {this.offline = false});

  final Bootstrap bootstrap;

  /// True when the server could not be reached and the saved copy of the
  /// launch data is being used.
  final bool offline;
}

/// The server says this build is too old to talk to it.
class UpdateRequired extends SessionState {
  const UpdateRequired({
    required this.current,
    required this.minimum,
    required this.latest,
  });

  final AppVersion current;
  final AppVersion minimum;
  final AppVersion latest;
}

final appVersionProvider = Provider<AppVersion>(
  (ref) => const AppVersion(1, 0, 0),
);

/// Counts the times an administrator changed what the signed-in user may do
/// (found by a quiet refresh). The shell shows a short note for each.
class AccessNotice extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final accessNoticeProvider = NotifierProvider<AccessNotice, int>(
  AccessNotice.new,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Owns the sign-in state: restores it at launch, signs in and out, and reacts
/// when the server says the session is over (401 anywhere in the app).
class SessionController extends Notifier<SessionState> {
  static const _bootstrapKey = 'bootstrap';

  @override
  SessionState build() {
    unawaited(Future<void>.microtask(restore));
    return const SessionLoading();
  }

  /// The last launch data seen. Screens still on display for the frame in
  /// which the user signs out read this instead of failing.
  Bootstrap? lastBootstrap;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Cold start. A stored token is checked with one `/bootstrap` call; if the
  /// phone is offline the saved copy of that answer keeps the app usable.
  Future<void> restore() async {
    final store = ref.read(tokenStoreProvider);
    // Locked behind the fingerprint: wait for the person, ask the server nothing yet.
    if (store.isProtected) {
      state = _lockedHint();
      return;
    }
    final token = await store.read();
    if (token == null || token.isEmpty) {
      state = const SignedOut();
      return;
    }
    await _loadBootstrap(allowOfflineCopy: true);
  }

  /// Signs in and loads the launch data. Throws a [Failure] (wrong password,
  /// deactivated account, rate limit, no connection...) for the form to show.
  Future<void> signIn({required String email, required String password}) async {
    final result = await _repo.login(
      email: email,
      password: password,
      deviceName: _deviceName(),
    );
    final store = ref.read(tokenStoreProvider);
    // A password sign-in always starts clean: an old fingerprint-locked copy of
    // an earlier session must not be left behind.
    await store.clear();
    await store.write(result.token);
    await ref.read(appPrefsProvider).setLastEmail(email.trim());
    try {
      await _loadBootstrap(allowOfflineCopy: false, throwOnFailure: true);
    } on Failure {
      // A token with no launch data is useless: do not stay half signed in.
      await store.clear();
      rethrow;
    }
    // Right after a password sign-in is the moment to offer fingerprint unlock.
    unawaited(ref.read(biometricOfferProvider.notifier).consider());
  }

  // ---- Fingerprint / screen lock: the saved session is locked behind the
  // phone's prompt (a crypto-bound key, see core/security/biometric_vault.dart).

  static const _lockChangedMessage =
      "Your phone's fingerprints or screen lock changed, so for your safety "
      'please sign in with your password again.';

  /// "Welcome back, Name": read from the saved launch data (no network).
  SessionLocked _lockedHint() {
    try {
      final saved = ref
          .read(readCacheProvider)
          .get(_bootstrapKey, ttl: const Duration(days: 365));
      final raw = saved?.value;
      if (raw is Map) {
        final user = AuthUser.fromJson(
          Map<String, dynamic>.from((raw['user'] as Map?) ?? const {}),
        );
        return SessionLocked(name: user.name, roleLabel: user.roleLabel);
      }
    } catch (_) {
      // No saved copy: the panel greets without a name.
    }
    return const SessionLocked();
  }

  /// Opens the phone's prompt for a locked session; when it succeeds the launch
  /// data is loaded and the app opens. Returns why it did not work (null = it did).
  Future<VaultFailure?> unlockSaved() async {
    if (state is! SessionLocked) return null;
    final VaultFailure? failure = await _openVault();
    if (failure != null) return failure;
    await _loadBootstrap(allowOfflineCopy: true);
    return null;
  }

  /// The prompt itself. A key the phone destroyed (new fingerprint, screen lock
  /// removed) or an empty vault ends this session with an explanation.
  Future<VaultFailure?> _openVault() async {
    try {
      final token = await ref.read(tokenStoreProvider).unlock();
      if (token != null && token.isNotEmpty) return null;
      await lockChanged();
      return VaultFailure.invalidated;
    } on VaultException catch (e) {
      if (e.failure == VaultFailure.invalidated ||
          e.failure == VaultFailure.notAvailable) {
        await lockChanged();
      }
      return e.failure;
    }
  }

  /// Same prompt for an already open app that locked itself after a while.
  Future<VaultFailure?> reauthenticate() => _openVault();

  /// The saved fingerprint session cannot be opened any more: forget it and
  /// ask for the password, saying why.
  Future<void> lockChanged() async {
    await _forget();
    state = const SignedOut(message: _lockChangedMessage);
  }

  /// "Use password instead" on the locked screen: there is no token in memory
  /// to revoke on the server, so only this phone forgets it.
  Future<void> signOutLocked() async {
    await _forget();
    state = const SignedOut();
  }

  Future<void> refreshBootstrap() async {
    final current = state;
    if (current is! SignedIn) return;
    try {
      await _loadBootstrap(allowOfflineCopy: true);
    } on Failure {
      // Keep what we have.
    }
  }

  // ---- Live permissions: an admin changes this user's access on the web and
  // the app follows without a sign-out. Three triggers, no timers: the server's
  // `X-Permissions-Version` header differs, a 403, and the app coming back to the
  // foreground. All of them end in the same quiet re-read of `/bootstrap`.

  /// A refresh that was asked for again within this long of the last one is dropped.
  static const syncDebounce = Duration(seconds: 3);

  /// Coming back from the background re-reads at most this often.
  static const resumeEvery = Duration(seconds: 60);

  /// Replaced in tests.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  Future<void>? _syncing;
  DateTime? _lastSync;

  /// A response carried permissions version [version].
  void onServerPermissionsVersion(String version) {
    final s = state;
    if (s is! SignedIn || version == s.bootstrap.user.permissionsVersion) {
      return;
    }
    unawaited(syncPermissions());
  }

  /// A request was refused (403): the screen may show something no longer allowed.
  void onForbidden() => unawaited(syncPermissions());

  /// The app is in front again.
  void onResume() => unawaited(syncPermissions(minGap: resumeEvery));

  /// Re-reads `/bootstrap` quietly. One at a time (callers share the running
  /// one), and not again within [minGap] of the last. Never signs out except on a
  /// 401 (the network layer handles that), never shows the offline state, never
  /// replaces anything that did not change (so open forms keep their text).
  Future<void> syncPermissions({Duration minGap = syncDebounce}) {
    final running = _syncing;
    if (running != null) return running;
    if (state is! SignedIn) return Future.value();
    final last = _lastSync;
    if (last != null && clock().difference(last) < minGap) {
      return Future.value();
    }
    return _syncing = _sync().whenComplete(() => _syncing = null);
  }

  Future<void> _sync() async {
    try {
      final boot = await _repo.bootstrap();
      final before = state;
      if (before is! SignedIn) return; // signed out while waiting
      await ref.read(readCacheProvider).put(_bootstrapKey, boot.raw);
      final next = _gate(boot);
      if (next is SignedIn &&
          !before.offline &&
          _fingerprint(before.bootstrap.raw) == _fingerprint(boot.raw)) {
        return;
      }
      state = next;
      if (next is! SignedIn || !before.bootstrap.user.sameAccessAs(boot.user)) {
        ref.read(accessNoticeProvider.notifier).bump();
      }
    } on Failure {
      // Silent: a bad moment must not disturb the screen.
    } finally {
      _lastSync = clock();
    }
  }

  /// The launch data without the server clock, which changes on every call.
  static String _fingerprint(Map<String, dynamic> raw) =>
      jsonEncode(Map<String, dynamic>.of(raw)..remove('server_time'));

  /// Signs out this phone only.
  Future<void> signOut() async {
    try {
      await _repo.logout();
    } on Failure {
      // Even if the server cannot be reached the phone must forget the token.
    }
    await _forget();
    state = const SignedOut();
  }

  /// Signs out every device (this one included).
  Future<void> signOutEverywhere() async {
    await _repo.logoutEverywhere();
    await _forget();
    state = const SignedOut();
  }

  /// The server answered 401: the token is dead.
  void expire() {
    if (state is SignedOut) return;
    unawaited(_forget());
    state = const SignedOut(
      message: 'Your session has ended. Please sign in again.',
    );
  }

  Future<void> _forget() async {
    await ref.read(tokenStoreProvider).clear();
    await ref.read(readCacheProvider).clearAll();
  }

  Future<void> _loadBootstrap({
    required bool allowOfflineCopy,
    bool throwOnFailure = false,
  }) async {
    try {
      final boot = await _repo.bootstrap();
      await ref.read(readCacheProvider).put(_bootstrapKey, boot.raw);
      state = _gate(boot);
      _lastSync = clock();
    } on UnauthorizedFailure {
      await _forget();
      state = const SignedOut(
        message: 'Your session has ended. Please sign in again.',
      );
      if (throwOnFailure) rethrow;
    } on Failure catch (f) {
      final saved = allowOfflineCopy
          ? ref
                .read(readCacheProvider)
                .get(_bootstrapKey, ttl: const Duration(days: 365))
          : null;
      if (saved != null &&
          saved.value is Map &&
          (f is NetworkFailure || f is TimeoutFailure || f is ServerFailure)) {
        state = _gate(
          Bootstrap.fromJson(Map<String, dynamic>.from(saved.value! as Map)),
          offline: true,
        );
        return;
      }
      if (throwOnFailure) rethrow;
      // Token present but the server is unreachable and nothing is saved:
      // let the user try again from Sign in instead of spinning forever.
      state = SignedOut(message: f.userMessage);
    }
  }

  SessionState _gate(Bootstrap boot, {bool offline = false}) {
    lastBootstrap = boot;
    final current = ref.read(appVersionProvider);
    if (current < boot.minAppVersion) {
      return UpdateRequired(
        current: current,
        minimum: boot.minAppVersion,
        latest: boot.latestAppVersion,
      );
    }
    return SignedIn(boot, offline: offline);
  }

  String _deviceName() {
    if (kIsWeb) return 'web-app';
    try {
      return 'app-${Platform.operatingSystem}';
    } catch (_) {
      return 'mobile-app';
    }
  }
}
