import 'package:flutter/material.dart';

import 'colors.dart';

/// Semantic colours for one theme. Read them with `context.tokens`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.info,
    required this.violet,
    required this.danger,
    required this.shimmerBase,
    required this.shimmerHighlight,
    required this.scrim,
  });

  final Brightness brightness;

  /// Page background.
  final Color bg;

  /// Cards, list rows, inputs (solid: lists never use blur).
  final Color surface;

  /// Sheets, selected rows, elevated cards.
  final Color surfaceRaised;
  final Color border;

  final Color text;
  final Color textSecondary;
  final Color textMuted;

  /// Brand gold for fills and icons.
  final Color accent;

  /// Gold that is readable as *text* on [bg]/[surface] in this theme.
  final Color accentText;

  /// Text/icon colour on a gold fill.
  final Color onAccent;

  final Color success;
  final Color warning;
  final Color info;
  final Color violet;
  final Color danger;

  final Color shimmerBase;
  final Color shimmerHighlight;
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  /// Background of bottom sheets: lighter than the page in dark mode, the page
  /// colour in light mode, so the cards inside (which use [surface]) stand out.
  Color get sheet => isDark ? surfaceRaised : bg;

  Color statusColor(AppointmentStatus s) => switch (s) {
    AppointmentStatus.pending => warning,
    AppointmentStatus.confirmed => info,
    AppointmentStatus.rescheduled => violet,
    AppointmentStatus.completed => success,
    AppointmentStatus.cancelled => danger,
  };

  static const dark = AppTokens(
    brightness: Brightness.dark,
    bg: AppColors.ink,
    surface: Color(0xFF17110C),
    surfaceRaised: Color(0xFF221912),
    border: Color(0xFF33261B),
    text: AppColors.cream,
    textSecondary: Color(0xFFC9BFAF),
    textMuted: Color(0xFF8C8173),
    accent: AppColors.gold,
    accentText: Color(0xFFE2C98F),
    onAccent: AppColors.ink,
    success: Color(0xFF5BD68A),
    warning: Color(0xFFF2B84B),
    info: Color(0xFF6FB4FF),
    violet: Color(0xFFB18CFF),
    danger: Color(0xFFFF7A70),
    shimmerBase: Color(0xFF1E1610),
    shimmerHighlight: Color(0xFF30241A),
    scrim: Color(0xB3000000),
  );

  static const light = AppTokens(
    brightness: Brightness.light,
    bg: Color(0xFFFAF7F2),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF3EDE3),
    border: Color(0xFFE6DCCB),
    text: Color(0xFF1A120C),
    textSecondary: Color(0xFF5E5246),
    textMuted: Color(0xFF706455),
    accent: AppColors.gold,
    accentText: Color(0xFF8A5A12),
    onAccent: AppColors.ink,
    success: Color(0xFF1A7A42),
    warning: Color(0xFF965F10),
    info: Color(0xFF2B6CB0),
    violet: Color(0xFF6B46C1),
    danger: Color(0xFFC53030),
    shimmerBase: Color(0xFFEFE8DC),
    shimmerHighlight: Color(0xFFFBF8F2),
    scrim: Color(0x80000000),
  );

  @override
  AppTokens copyWith({Color? bg}) => AppTokens(
    brightness: brightness,
    bg: bg ?? this.bg,
    surface: surface,
    surfaceRaised: surfaceRaised,
    border: border,
    text: text,
    textSecondary: textSecondary,
    textMuted: textMuted,
    accent: accent,
    accentText: accentText,
    onAccent: onAccent,
    success: success,
    warning: warning,
    info: info,
    violet: violet,
    danger: danger,
    shimmerBase: shimmerBase,
    shimmerHighlight: shimmerHighlight,
    scrim: scrim,
  );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      border: l(border, other.border),
      text: l(text, other.text),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      accentText: l(accentText, other.accentText),
      onAccent: l(onAccent, other.onAccent),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      info: l(info, other.info),
      violet: l(violet, other.violet),
      danger: l(danger, other.danger),
      shimmerBase: l(shimmerBase, other.shimmerBase),
      shimmerHighlight: l(shimmerHighlight, other.shimmerHighlight),
      scrim: l(scrim, other.scrim),
    );
  }
}

extension TokensContext on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.dark;
}
