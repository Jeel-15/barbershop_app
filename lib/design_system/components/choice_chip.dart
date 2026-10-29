import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'haptics.dart';
import 'pressable.dart';

/// A small selectable pill: gold when chosen, outlined when not. Used for
/// every "pick one" in sheets (date, time of day, barber, slot times), so they
/// all look and size the same.
class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Pressable(
      haptic: false,
      minSize: 0,
      semanticLabel: label,
      onTap: () {
        if (!selected) AppHaptics.select();
        onTap();
      },
      child: AnimatedContainer(
        duration: AppMotion.fast,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.goldGradient : null,
          color: selected ? null : t.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? Colors.transparent : t.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.ink : t.textSecondary,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppType.label.copyWith(
                fontSize: 13,
                color: selected ? AppColors.ink : t.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
