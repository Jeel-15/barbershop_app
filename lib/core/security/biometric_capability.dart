import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// What this phone can use to open the app, in the words the person knows.
enum BiometricKind {
  /// No screen lock, no hardware, or not supported: the feature is not offered.
  none,

  /// A fingerprint (or any strong biometric the system accepts).
  fingerprint,

  /// iPhone-style face recognition (reserved for iOS).
  face,

  /// Only the phone's PIN / pattern / password (weak face unlock and
  /// "nothing enrolled" both land here).
  screenLock,
}

extension BiometricKindWords on BiometricKind {
  bool get available => this != BiometricKind.none;

  /// "Unlock with fingerprint" / "Unlock with face" / "Unlock with screen lock".
  String get unlockWith => switch (this) {
    BiometricKind.fingerprint => 'fingerprint',
    BiometricKind.face => 'face',
    _ => 'phone screen lock',
  };

  /// Short name for rows and toasts: "Fingerprint unlock is on."
  String get noun => switch (this) {
    BiometricKind.fingerprint => 'Fingerprint unlock',
    BiometricKind.face => 'Face unlock',
    _ => 'Screen lock unlock',
  };
}

/// Used only to decide whether to offer the feature and what to call it.
/// It is never the gate: the gate is the key in [BiometricVault].
abstract interface class BiometricCapability {
  Future<BiometricKind> kind();
}

class LocalAuthCapability implements BiometricCapability {
  LocalAuthCapability([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<BiometricKind> kind() async {
    try {
      if (!await _auth.isDeviceSupported()) return BiometricKind.none;
      final types = await _auth.getAvailableBiometrics();
      if (types.contains(BiometricType.fingerprint) ||
          types.contains(BiometricType.strong)) {
        return BiometricKind.fingerprint;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          types.contains(BiometricType.face)) {
        return BiometricKind.face;
      }
      return BiometricKind.screenLock;
    } catch (_) {
      return BiometricKind.none;
    }
  }
}
