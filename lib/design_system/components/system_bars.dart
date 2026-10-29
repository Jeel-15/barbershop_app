import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The status bar (clock, battery, signal) and the bottom bar of the phone, over
/// the screen's own background: transparent, with icons that can be read.
///
/// Icons must be the opposite of what is behind them: light icons on a dark
/// screen, dark icons on a light one. One fixed style (the old behaviour: always
/// light) leaves white icons on a cream screen, which look like "nothing is
/// there". So the style follows the theme, and a screen that is always dark
/// (the splash, the welcome video) says so with [lightIcons].
class SystemBars extends StatelessWidget {
  const SystemBars({super.key, this.lightIcons, required this.child});

  /// True = light icons (for a dark screen), false = dark icons, null = follow
  /// the current theme.
  final bool? lightIcons;
  final Widget child;

  /// The overlay style for a screen with [light] icons.
  static SystemUiOverlayStyle styleFor({required bool light}) {
    final icons = light ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: icons,
      // iOS names it the other way round (the brightness of the bar itself).
      statusBarBrightness: light ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: icons,
      // Android would otherwise add its own grey scrim behind the bars.
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final light = lightIcons ?? Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: styleFor(light: light),
      child: child,
    );
  }
}
