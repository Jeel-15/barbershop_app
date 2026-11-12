import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'pressable.dart';

enum AppButtonVariant {
  primary,
  secondary,
  ghost,
  danger,

  /// Green: finishing something (Complete).
  success,

  /// Outlined red: a destructive choice that should not shout (Cancel).
  dangerOutline,
}

/// The one button. Primary = gold, Secondary = outlined surface, Ghost = text,
/// Danger = destructive. [loading] keeps the width and blocks double taps.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.expand = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool loading;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final disabled = onPressed == null;
    final height = compact ? 44.0 : 54.0;

    final (
      Color fg,
      Gradient? gradient,
      Color? fill,
      Color? border,
    ) = switch (variant) {
      AppButtonVariant.primary => (
        t.onAccent,
        AppColors.goldGradient,
        null,
        null,
      ),
      AppButtonVariant.secondary => (t.text, null, t.surface, t.border),
      AppButtonVariant.ghost => (t.accentText, null, null, null),
      AppButtonVariant.danger => (Colors.white, null, t.danger, null),
      AppButtonVariant.success => (Colors.white, null, t.success, null),
      AppButtonVariant.dangerOutline => (
        t.danger,
        null,
        t.surface,
        t.danger.withValues(alpha: 0.55),
      ),
    };

    final content = AnimatedSwitcher(
      duration: AppMotion.fast,
      child: loading
          ? SizedBox(
              key: const ValueKey('spin'),
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: fg),
                  const SizedBox(width: 8),
                ],
                // A label that is a little too long shrinks to fit instead of being
                // cut ("Yes, confi...").
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: AppText.ui(
                        compact ? 14 : 16,
                        weight: FontWeight.w800,
                        color: fg,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );

    final button = Pressable(
      onTap: (disabled || loading) ? null : onPressed,
      semanticLabel: label,
      minSize: height,
      child: Opacity(
        opacity: disabled && !loading ? 0.45 : 1,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: gradient,
            color: fill,
            borderRadius: BorderRadius.circular(height / 2.6),
            border: border == null ? null : Border.all(color: border),
            boxShadow: variant == AppButtonVariant.primary && !disabled
                ? [
                    BoxShadow(
                      color: AppColors.gold.withValues(
                        alpha: t.isDark ? 0.28 : 0.35,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: content,
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
