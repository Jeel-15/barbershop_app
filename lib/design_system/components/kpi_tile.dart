import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'money_text.dart';
import 'pressable.dart';
import 'skeleton.dart';

/// Number card (Home, reports). [highlight] = gold fill.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.valueText,
    this.format,
    this.caption,
    this.highlight = false,
    this.loading = false,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// Animated count-up of [value] formatted by [format]; or fixed [valueText].
  final double? value;
  final String Function(double)? format;
  final String? valueText;
  final String? caption;
  final bool highlight;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = highlight ? AppColors.ink : t.text;
    final sub = highlight
        ? AppColors.ink.withValues(alpha: 0.7)
        : t.textSecondary;

    final card = Container(
      padding: const EdgeInsets.all(AppSpace.md + 2),
      decoration: BoxDecoration(
        gradient: highlight ? AppColors.goldGradient : null,
        color: highlight ? null : t.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: highlight ? Colors.transparent : t.border),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: loading
          ? const SkeletonLoader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 18, circle: true),
                  SizedBox(height: 14),
                  SkeletonBox(width: 70, height: 22),
                  SizedBox(height: 8),
                  SkeletonBox(width: 50, height: 11),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: highlight ? AppColors.ink : t.accentText,
                ),
                const SizedBox(height: AppSpace.md),
                DefaultTextStyle.merge(
                  style: TextStyle(color: fg),
                  child: value != null && format != null
                      ? CountUpText(value: value!, builder: format!)
                      : Text(
                          valueText ?? '-',
                          style: AppType.kpiNumber.copyWith(color: fg),
                        ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(color: sub),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: sub, fontSize: 11.5),
                  ),
              ],
            ),
    );
    return onTap == null
        ? card
        : Pressable(onTap: onTap, minSize: 0, scale: 0.98, child: card);
  }
}
