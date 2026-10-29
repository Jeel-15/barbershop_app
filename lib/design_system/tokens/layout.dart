import 'package:flutter/widgets.dart';

/// 4-pt spacing grid.
class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Horizontal page gutter.
  static const double page = 20;
}

class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get control => BorderRadius.circular(md);
}

/// One motion language: short, ease-out, one motion per intent.
class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 380);

  static const curve = Curves.easeOutCubic;
  static const curveIn = Curves.easeInCubic;
  static const spring = Curves.easeOutBack;
}

/// Minimum touch target (accessibility).
const double kMinTarget = 48;
