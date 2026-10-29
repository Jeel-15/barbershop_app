import 'package:flutter/material.dart';

import '../../core/utils/shop_time.dart';
import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/layout.dart';
import '../tokens/typography.dart';
import 'haptics.dart';
import 'pressable.dart';

/// Horizontal day picker (calendar, slot picker). [markers] puts a dot under
/// days that have something booked; today has a ring; [closed] days are dimmed.
class DateStrip extends StatefulWidget {
  const DateStrip({
    super.key,
    required this.selected,
    required this.onSelected,
    this.markers = const {},
    this.closed = const {},
    this.pastDays = 7,
    this.futureDays = 60,
  });

  final DateTime selected;
  final ValueChanged<DateTime> onSelected;
  final Set<DateTime> markers;
  final Set<DateTime> closed;
  final int pastDays;
  final int futureDays;

  @override
  State<DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<DateStrip> {
  static const _cell = 54.0;
  static const _gap = 8.0;
  late final ScrollController _scroll;
  late final DateTime _start = ShopTime.today().subtract(
    Duration(days: widget.pastDays),
  );

  int _indexOf(DateTime d) => ShopTime.dateOnly(
    d,
  ).difference(_start).inDays.clamp(0, widget.pastDays + widget.futureDays);

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
      initialScrollOffset: _offsetFor(widget.selected, 390),
    );
  }

  double _offsetFor(DateTime d, double viewport) =>
      (_indexOf(d) * (_cell + _gap) - viewport / 2 + _cell / 2 + AppSpace.page)
          .clamp(0.0, double.infinity);

  @override
  void didUpdateWidget(covariant DateStrip old) {
    super.didUpdateWidget(old);
    if (!ShopTime.isSameDay(old.selected, widget.selected) &&
        _scroll.hasClients) {
      _scroll.animateTo(
        _offsetFor(
          widget.selected,
          _scroll.position.viewportDimension,
        ).clamp(0.0, _scroll.position.maxScrollExtent),
        duration: AppMotion.normal,
        curve: AppMotion.curve,
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final total = widget.pastDays + widget.futureDays + 1;
    return SizedBox(
      height: 84,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.page),
        itemCount: total,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, i) {
          final d = _start.add(Duration(days: i));
          final on = ShopTime.isSameDay(d, widget.selected);
          final today = ShopTime.isToday(d);
          final closed = widget.closed.any((c) => ShopTime.isSameDay(c, d));
          final marked = widget.markers.any((m) => ShopTime.isSameDay(m, d));
          return Pressable(
            haptic: false,
            minSize: 0,
            semanticLabel: ShopTime.relativeDay(d),
            onTap: () {
              AppHaptics.select();
              widget.onSelected(d);
            },
            child: Opacity(
              opacity: closed && !on ? 0.45 : 1,
              child: AnimatedContainer(
                duration: AppMotion.fast,
                width: _cell,
                decoration: BoxDecoration(
                  gradient: on ? AppColors.goldGradient : null,
                  color: on ? null : t.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: on
                        ? Colors.transparent
                        : (today ? t.accent : t.border),
                    width: today && !on ? 1.6 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ShopTime.weekdayShort(d).toUpperCase(),
                      style: AppType.overline.copyWith(
                        fontSize: 10.5,
                        letterSpacing: 1,
                        color: on
                            ? AppColors.ink.withValues(alpha: 0.75)
                            : t.textMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${d.day}',
                      style: AppType.heading.copyWith(
                        fontSize: 20,
                        color: on ? AppColors.ink : t.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: marked
                            ? (on ? AppColors.ink : t.accent)
                            : Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
