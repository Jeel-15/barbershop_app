import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Why the vault did not hand over (or take) the token.
enum VaultFailure {
  /// The person closed the prompt or pressed Cancel. Nothing is wrong.
  cancelled,

  /// Too many wrong tries; the phone asks for a wait or its PIN.
  lockedOut,

  /// The phone's fingerprints or screen lock changed: Android destroyed the
  /// key on purpose. The saved session cannot be opened any more.
  invalidated,

  /// No screen lock / no hardware / Android older than 9: biometric storage
  /// cannot work on this phone.
  notAvailable,

  unknown,
}

class VaultException implements Exception {
  const VaultException(this.failure, [this.detail]);

  final VaultFailure failure;

  /// The platform's own words, for logs only (never shown, never a token).
  final String? detail;

  /// Reads the Android side's message. `flutter_secure_storage` reports a
  /// failed prompt as `Biometric authentication error [N]: ...` where N is the
  /// BiometricPrompt error code, an unusable phone as `BIOMETRIC_UNAVAILABLE`,
  /// and a destroyed key as a Keystore exception name.
  factory VaultException.fromPlatform(Object error) {
    final text = switch (error) {
      PlatformException(:final message, :final details, :final code) =>
        '$code $message $details',
      _ => error.toString(),
    };
    final lower = text.toLowerCase();

    if (lower.contains('biometric_unavailable')) {
      return VaultException(VaultFailure.notAvailable, text);
    }
    final code = RegExp(
      r'Biometric authentication error \[(\d+)\]',
    ).firstMatch(text)?.group(1);
    if (code != null) {
      return VaultException(switch (int.parse(code)) {
        5 || 10 || 13 => VaultFailure.cancelled,
        7 || 9 => VaultFailure.lockedOut,
        1 || 11 || 12 || 14 => VaultFailure.notAvailable,
        _ => VaultFailure.unknown,
      }, text);
    }
    if (lower.contains('invalidated') ||
        lower.contains('keypermanentlyinvalidated') ||
        lower.contains('invalidkeyexception') ||
        lower.contains('aeadbadtag') ||
        lower.contains('badpadding') ||
        lower.contains('key not found')) {
      return VaultException(VaultFailure.invalidated, text);
    }
    return VaultException(VaultFailure.unknown, text);
  }

  @override
  String toString() => 'VaultException($failure)';
}

/// A safe whose key only works right after the person proves who they are
/// (fingerprint, strong face, or the phone's PIN). Holds the session token.
///
/// `save` and `read` open the phone's own prompt; `hasToken` and `delete` never do.
abstract interface class BiometricVault {
  Future<bool> hasToken();

  /// Opens the prompt, then stores [token].
  Future<void> save(String token);

  /// Opens the prompt, then returns the token (null if nothing is stored).
  Future<String?> read();

  Future<void> delete();
}

/// Android Keystore, crypto-bound (OWASP MASTG): an AES-GCM key created with
/// `setUserAuthenticationRequired(true)`, valid for ONE use, destroyed when a
/// fingerprint is added or the screen lock is removed, used through a
/// `BiometricPrompt` CryptoObject, so a faked "success" gives nothing.
class SecureBiometricVault implements BiometricVault {
  SecureBiometricVault({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions.biometric(
              enforceBiometrics: true,
              // A fresh prompt for every read or write; the key is never cached.
              requireBiometricsPerOperation: true,
              // Strong biometric, or the phone's PIN / pattern as the way out of a lock-out.
              biometricType: AndroidBiometricType.biometricOrDeviceCredential,
              // Face and other passive methods open it without an extra tap.
              requireBiometricConfirmation: false,
              // A failed prompt must never erase the saved session; we delete on purpose.
              resetOnError: false,
              storageNamespace: 'biometric_vault',
              biometricPromptTitle: 'Unlock Rosenthal',
              biometricPromptSubtitle: 'Confirm it is you to continue',
            ),
          );

  static const _key = 'auth_token';
  final FlutterSecureStorage _storage;

  @override
  Future<bool> hasToken() async {
    try {
      return await _storage.containsKey(key: _key);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> save(String token) async {
    try {
      await _storage.write(key: _key, value: token);
    } catch (e) {
      throw VaultException.fromPlatform(e);
    }
  }

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _key);
    } catch (e) {
      throw VaultException.fromPlatform(e);
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing to remove, or the key is already gone: the goal is reached.
    }
  }
}
