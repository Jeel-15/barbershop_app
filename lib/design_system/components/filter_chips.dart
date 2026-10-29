import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'haptics.dart';
import 'pressable.dart';

class ChipOption<T> {
  const ChipOption(this.value, this.label, {this.count, this.icon});

  final T value;
  final String label;
  final int? count;
  final IconData? icon;
}

/// Horizontal single-choice chips (status tabs, date ranges). Selected = gold.
class ChipsRow<T> extends StatelessWidget {
  const ChipsRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.page),
    this.compact = false,
  });

  final List<ChipOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  /// Smaller chips (36 px) for dense screens like the appointment list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      height: compact ? 36 : 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: options.length,
        separatorBuilder: (_, _) => SizedBox(width: compact ? 6 : 8),
        itemBuilder: (context, i) {
          final o = options[i];
          final on = o.value == selected;
          return Pressable(
            haptic: false,
            minSize: 40,
            semanticLabel: o.label,
            onTap: () {
              if (!on) AppHaptics.select();
              onChanged(o.value);
            },
            child: AnimatedContainer(
              duration: AppMotion.fast,
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: on ? AppColors.goldGradient : null,
                color: on ? null : t.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: on ? Colors.transparent : t.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (o.icon != null) ...[
                    Icon(
                      o.icon,
                      size: 15,
                      color: on ? AppColors.ink : t.textSecondary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    o.label,
                    style: AppType.label.copyWith(
                      fontSize: 13,
                      color: on ? AppColors.ink : t.text,
                    ),
                  ),
                  if (o.count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${o.count}',
                      style: AppType.label.copyWith(
                        fontSize: 12,
                        color: on
                            ? AppColors.ink.withValues(alpha: 0.7)
                            : t.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Compact segmented control with a sliding thumb (2-4 short options).
class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<ChipOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final index = options
        .indexWhere((o) => o.value == selected)
        .clamp(0, options.length - 1);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: t.border),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / options.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: AppMotion.normal,
                curve: AppMotion.curve,
                left: w * index,
                width: w,
                top: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.goldGradient,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final o in options)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: o.value == selected,
                        label: o.label,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            AppHaptics.select();
                            onChanged(o.value);
                          },
                          child: Center(
                            child: Text(
                              o.label,
                              style: AppType.label.copyWith(
                                fontSize: 13,
                                color: o.value == selected
                                    ? AppColors.ink
                                    : t.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
