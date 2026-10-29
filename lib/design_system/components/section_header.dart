import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'pressable.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.subtitle,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Less air above (Home stacks many blocks and wants a shorter page).
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.page,
        dense ? AppSpace.md : AppSpace.xl,
        AppSpace.page,
        dense ? AppSpace.xs : AppSpace.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.heading.copyWith(color: t.text)),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: AppType.caption.copyWith(color: t.textMuted),
                  ),
              ],
            ),
          ),
          if (actionLabel != null)
            Pressable(
              onTap: onAction,
              minSize: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  actionLabel!,
                  style: AppType.label.copyWith(
                    color: t.accentText,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
