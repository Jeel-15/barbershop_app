import 'package:flutter/services.dart';

/// One place for haptic feedback so it can be switched off in Settings.
class AppHaptics {
  static bool enabled = true;

  /// Light tap on a control.
  static void tap() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// A choice was made (tab, chip, picker).
  static void select() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// Something important completed (confirm, saved, paid).
  static void success() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  /// A warning or a refused action.
  static void warning() {
    if (enabled) HapticFeedback.heavyImpact();
  }
}
