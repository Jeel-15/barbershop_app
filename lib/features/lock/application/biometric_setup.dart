import 'package:barbershop_app/core/providers.dart';
import 'package:barbershop_app/core/security/biometric_capability.dart';
import 'package:barbershop_app/core/security/biometric_vault.dart';
import 'package:barbershop_app/core/storage/storage.dart';
import 'package:barbershop_app/features/lock/domain/lock_timeout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What happened when the person asked to turn fingerprint unlock on.
enum EnableOutcome {
  enabled,

  /// They closed the phone's prompt. Nothing changed, nothing to say.
  cancelled,

  /// The phone cannot do it (no screen lock, too old...).
  notAvailable,

  /// The phone said no for another reason (lock-out...).
  failed,
}

/// Turning the feature on and off, and deciding when to offer it.
class BiometricSetup {
  BiometricSetup(this._store, this._capability, this._prefs);

  final ProtectableTokenStore _store;
  final BiometricCapability _capability;
  final AppPrefs _prefs;

  /// After this many "Not now" answers the offer stops; Settings stays.
  static const maxDeclines = 2;

  Future<BiometricKind> kind() => _capability.kind();

  bool get enabled => _store.isProtected;

  /// True right after a password sign-in when the phone can do it, the person
  /// has not turned it on and has not said "Not now" twice.
  Future<bool> shouldOffer() async {
    if (enabled || _prefs.biometricOfferDeclines >= maxDeclines) return false;
    return (await kind()).available;
  }

  /// Opens the phone's prompt once; the session is locked behind it only if
  /// that succeeds.
  Future<EnableOutcome> enable() async {
    try {
      await _store.protect();
      return EnableOutcome.enabled;
    } on VaultException catch (e) {
      return switch (e.failure) {
        VaultFailure.cancelled => EnableOutcome.cancelled,
        VaultFailure.notAvailable => EnableOutcome.notAvailable,
        _ => EnableOutcome.failed,
      };
    }
  }

  Future<void> disable() => _store.unprotect();

  Future<void> declineOffer() =>
      _prefs.setBiometricOfferDeclines(_prefs.biometricOfferDeclines + 1);
}

final biometricSetupProvider = Provider<BiometricSetup>(
  (ref) => BiometricSetup(
    ref.watch(tokenStoreProvider),
    ref.watch(biometricCapabilityProvider),
    ref.watch(appPrefsProvider),
  ),
);

/// What this phone offers (fingerprint / screen lock / nothing).
final biometricKindProvider = FutureProvider<BiometricKind>(
  (ref) => ref.watch(biometricCapabilityProvider).kind(),
);

/// Becomes true after a password sign-in when the offer should be shown;
/// the shell shows the sheet once and resets it.
class BiometricOffer extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> consider() async {
    try {
      state = await ref.read(biometricSetupProvider).shouldOffer();
    } catch (_) {
      state = false; // never in the way of signing in
    }
  }

  void dismiss() => state = false;
}

final biometricOfferProvider = NotifierProvider<BiometricOffer, bool>(
  BiometricOffer.new,
);

/// The chosen time before the app locks (kept on this phone).
class LockTimeoutNotifier extends Notifier<LockTimeout> {
  @override
  LockTimeout build() =>
      LockTimeout.fromSeconds(ref.read(appPrefsProvider).lockTimeoutSeconds);

  Future<void> set(LockTimeout t) async {
    state = t;
    await ref.read(appPrefsProvider).setLockTimeoutSeconds(t.seconds);
  }
}

final lockTimeoutProvider = NotifierProvider<LockTimeoutNotifier, LockTimeout>(
  LockTimeoutNotifier.new,
);
