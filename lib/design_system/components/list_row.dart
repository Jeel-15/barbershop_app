import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'pressable.dart';

/// Standard row: leading, title/subtitle, trailing, optional chevron.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final row = Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: AppSpace.md,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(
                    color: destructive ? t.danger : t.text,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.caption.copyWith(color: t.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.sm),
            trailing!,
          ],
          if (chevron) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: t.textMuted),
          ],
        ],
      ),
    );
    return onTap == null
        ? row
        : Pressable(onTap: onTap, scale: 0.99, minSize: 0, child: row);
  }
}

/// Rows inside one rounded card with hairline dividers (settings / More menu).
class AppListGroup extends StatelessWidget {
  const AppListGroup({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.page + 4,
              AppSpace.lg,
              AppSpace.page,
              AppSpace.sm,
            ),
            child: Text(
              title!.toUpperCase(),
              style: AppType.overline.copyWith(color: t.textMuted),
            ),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpace.page),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.card,
            border: Border.all(color: t.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    indent: AppSpace.lg,
                    endIndent: AppSpace.lg,
                    color: t.border,
                  ),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
