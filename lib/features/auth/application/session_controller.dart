import 'dart:async';
import 'dart:io' show Platform;

import 'package:barbershop_app/core/errors/failure.dart';
import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/utils/app_version.dart';
import 'package:barbershop_app/features/auth/data/auth_repository.dart';
import 'package:barbershop_app/features/auth/domain/bootstrap.dart';
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
    final token = await ref.read(tokenStoreProvider).read();
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
    await ref.read(tokenStoreProvider).write(result.token);
    await ref.read(appPrefsProvider).setLastEmail(email.trim());
    try {
      await _loadBootstrap(allowOfflineCopy: false, throwOnFailure: true);
    } on Failure {
      // A token with no launch data is useless: do not stay half signed in.
      await ref.read(tokenStoreProvider).clear();
      rethrow;
    }
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
