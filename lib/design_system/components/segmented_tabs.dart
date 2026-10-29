import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'pressable.dart';

/// One choice of [SegmentedTabs]: a label and an optional count.
class SegmentItem<T> {
  const SegmentItem(this.value, this.label, {this.count});

  final T value;
  final String label;
  final int? count;
}

/// Two or three views of one block under a single pill ("Today 3 | Upcoming 5"):
/// one block on the page instead of one block per view, so the page is shorter.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<SegmentItem<T>> items;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.border.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          for (final i in items)
            Expanded(
              child: Semantics(
                button: true,
                selected: i.value == selected,
                label: i.count == null ? i.label : '${i.label}, ${i.count}',
                excludeSemantics: true,
                child: Pressable(
                  onTap: () => onChanged(i.value),
                  minSize: 0,
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 8,
                    ),
                    decoration: BoxDecoration(
                      color: i.value == selected ? t.surface : null,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      boxShadow: i.value == selected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            i.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.label.copyWith(
                              fontSize: 13,
                              color: i.value == selected
                                  ? t.text
                                  : t.textSecondary,
                            ),
                          ),
                        ),
                        if (i.count != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: i.value == selected
                                  ? t.accent.withValues(alpha: 0.22)
                                  : t.border,
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                            child: Text(
                              '${i.count}',
                              style: AppType.caption.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: i.value == selected
                                    ? t.accentText
                                    : t.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
