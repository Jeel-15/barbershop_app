import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'money_text.dart';
import 'pressable.dart';

/// One small figure: coloured icon, counted-up number, label. Used for the
/// dashboard overview and anywhere a count needs a card.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final tile = Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.16),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: AppSpace.md),
          CountUpText(
            value: value.toDouble(),
            builder: (v) => '${v.round()}',
            duration: const Duration(milliseconds: 800),
            style: AppType.title.copyWith(color: t.text),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(
              color: t.textSecondary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Pressable(onTap: onTap, scale: 0.98, minSize: 0, child: tile);
  }
}

/// Lays tiles out in rows of [columns]; a short last row shares the full
/// width between its tiles, so no gap is left.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.tiles, this.columns = 3});

  final List<Widget> tiles;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <List<Widget>>[];
    for (var i = 0; i < tiles.length; i += columns) {
      rows.add(tiles.sublist(i, (i + columns).clamp(0, tiles.length)));
    }
    return Column(
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: AppSpace.sm + 2),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var c = 0; c < rows[r].length; c++) ...[
                  if (c > 0) const SizedBox(width: AppSpace.sm + 2),
                  Expanded(child: rows[r][c]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
