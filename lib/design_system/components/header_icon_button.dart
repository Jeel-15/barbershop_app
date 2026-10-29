import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';
import 'pressable.dart';

/// Round icon button for a screen header (search, filter...). [count] puts a
/// small gold badge on it (how many filters are on); [active] tints it.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count = 0,
    this.active = false,
  });

  final IconData icon;

  /// Read by screen readers (there is no text on the button).
  final String label;
  final VoidCallback onTap;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final on = active || count > 0;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap,
        minSize: 0,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: on ? t.accent.withValues(alpha: 0.16) : t.surface,
                  border: Border.all(color: on ? t.accent : t.border),
                ),
                child: Icon(icon, size: 21, color: on ? t.accentText : t.text),
              ),
              if (count > 0)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.goldGradient,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: t.bg, width: 1.5),
                    ),
                    child: Text(
                      '$count',
                      style: AppType.label.copyWith(
                        fontSize: 10.5,
                        color: AppColors.ink,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
