import 'package:barbershop_app/design_system/motion/page_transitions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';

/// Builds the dark and light [ThemeData] from the same tokens, so every
/// Material widget (inputs, sheets, dialogs, chips) already looks right.
class AppTheme {
  static ThemeData get dark => _build(AppTokens.dark);
  static ThemeData get light => _build(AppTokens.light);

  static ThemeData _build(AppTokens t) {
    final scheme = ColorScheme(
      brightness: t.brightness,
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accentText,
      onSecondary: t.onAccent,
      error: t.danger,
      onError: Colors.white,
      surface: t.surface,
      onSurface: t.text,
      surfaceContainerHighest: t.surfaceRaised,
      outline: t.border,
      outlineVariant: t.border,
    );

    TextStyle s(TextStyle style, Color color) => style.copyWith(color: color);
    final textTheme = TextTheme(
      displayLarge: s(AppType.largeTitle, t.text),
      displayMedium: s(AppType.largeTitle, t.text),
      headlineLarge: s(AppType.title, t.text),
      headlineMedium: s(AppType.title, t.text),
      headlineSmall: s(AppType.heading, t.text),
      titleLarge: s(AppType.heading, t.text),
      titleMedium: s(AppType.subheading, t.text),
      titleSmall: s(AppType.bodyStrong, t.text),
      bodyLarge: s(AppType.body, t.text),
      bodyMedium: s(AppType.body, t.text),
      bodySmall: s(AppType.caption, t.textSecondary),
      labelLarge: s(AppType.bodyStrong, t.text),
      labelMedium: s(AppType.label, t.textSecondary),
      labelSmall: s(AppType.overline, t.textMuted),
    );

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: AppRadius.control,
      borderSide: BorderSide(color: c, width: w),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      fontFamily: AppFonts.ui,
      extensions: [t],
      scaffoldBackgroundColor: t.bg,
      colorScheme: scheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // The sparkle splash compiles a shader the first time it is used (a visible
      // hitch on the first tap); the ripple is as clear and costs nothing.
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
        },
      ),
      dividerColor: t.border,
      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: s(AppType.heading, t.text),
        iconTheme: IconThemeData(color: t.text),
        systemOverlayStyle: t.isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: 15,
        ),
        hintStyle: s(AppType.body, t.textMuted),
        errorStyle: s(AppType.caption, t.danger),
        border: border(t.border),
        enabledBorder: border(t.border),
        focusedBorder: border(t.accent, 1.6),
        errorBorder: border(t.danger),
        focusedErrorBorder: border(t.danger, 1.6),
        disabledBorder: border(t.border.withValues(alpha: 0.5)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.sheet,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: t.sheet,
        showDragHandle: true,
        dragHandleColor: t.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: s(AppType.heading, t.text),
        contentTextStyle: s(AppType.body, t.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.isDark ? t.surfaceRaised : const Color(0xFF2A1F16),
        contentTextStyle: AppType.body.copyWith(color: AppColors.cream),
        actionTextColor: AppColors.goldLight,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surface,
        selectedColor: t.accent.withValues(alpha: 0.2),
        side: BorderSide(color: t.border),
        labelStyle: s(AppType.label, t.text),
        shape: const StadiumBorder(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.onAccent : t.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.accent : t.surfaceRaised,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.transparent : t.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? t.accent : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(t.onAccent),
        side: BorderSide(color: t.textMuted, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.border,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.accent,
        selectionColor: t.accent.withValues(alpha: 0.3),
        selectionHandleColor: t.accent,
      ),
    );
  }
}
