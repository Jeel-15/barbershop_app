import 'package:flutter/material.dart';

import 'colors.dart';

/// Bundled fonts (see pubspec): Playfair Display for brand/hero numbers,
/// Manrope for everything else.
class AppFonts {
  static const display = 'PlayfairDisplay';
  static const ui = 'Manrope';
}

/// Free-standing style helpers (used by brand screens that are always dark).
/// In regular screens read styles from `Theme.of(context).textTheme` or the
/// [AppType] scale so colours follow the theme.
class AppText {
  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.cream,
    double height = 1.1,
    double letterSpacing = 0,
  }) {
    return TextStyle(
      fontFamily: AppFonts.display,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      // Playfair's default numerals are old-style (they sit at different
      // heights); money and counts read better with lining figures.
      fontFeatures: const [FontFeature.liningFigures()],
    );
  }

  static TextStyle ui(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.cream,
    double letterSpacing = 0,
    double? height,
  }) {
    return TextStyle(
      fontFamily: AppFonts.ui,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

/// The type scale. Sizes are in logical pixels and scale with the OS text size.
class AppType {
  static const _ui = AppFonts.ui;

  static const largeTitle = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.15,
  );
  static const title = TextStyle(
    fontFamily: _ui,
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );
  static const heading = TextStyle(
    fontFamily: _ui,
    fontSize: 18,
    fontWeight: FontWeight.w800,
    height: 1.25,
  );
  static const subheading = TextStyle(
    fontFamily: _ui,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );
  static const body = TextStyle(
    fontFamily: _ui,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
  static const bodyStrong = TextStyle(
    fontFamily: _ui,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.4,
  );
  static const caption = TextStyle(
    fontFamily: _ui,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );
  static const label = TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );
  static const overline = TextStyle(
    fontFamily: _ui,
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.6,
    height: 1.3,
  );

  /// Hero numbers (KPI, totals): serif, tabular-friendly.
  static const heroNumber = TextStyle(
    fontFamily: AppFonts.display,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.05,
  );
  static const kpiNumber = TextStyle(
    fontFamily: _ui,
    fontSize: 24,
    fontWeight: FontWeight.w800,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const money = TextStyle(
    fontFamily: _ui,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
