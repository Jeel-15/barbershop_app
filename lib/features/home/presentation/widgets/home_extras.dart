import 'dart:math' as math;

import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/home/domain/dashboard.dart';
import 'package:flutter/material.dart';

enum _Insight { services, products }

/// Top services and top selling products in one card, with a switch between
/// them. Services are ranked bars (bookings and share); products are a donut
/// (units sold and share). No money on Home: the web computes the money column
/// with a formula that can double-count, and amounts live behind the eye on More.
class HomeInsightsCard extends StatefulWidget {
  const HomeInsightsCard({
    super.key,
    required this.services,
    required this.products,
  });

  final List<TopService> services;
  final List<TopProduct> products;

  @override
  State<HomeInsightsCard> createState() => _HomeInsightsCardState();
}

class _HomeInsightsCardState extends State<HomeInsightsCard> {
  _Insight? _picked;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hasServices = widget.services.isNotEmpty;
    final hasProducts = widget.products.isNotEmpty;
    final view =
        _picked ?? (hasServices ? _Insight.services : _Insight.products);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasServices && hasProducts) ...[
            SegmentedTabs<_Insight>(
              items: const [
                SegmentItem(_Insight.services, 'Top Services'),
                SegmentItem(_Insight.products, 'Top Selling Product'),
              ],
              selected: view,
              onChanged: (v) => setState(() {
                _picked = v;
                _all = false;
              }),
            ),
            const SizedBox(height: AppSpace.lg),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.md),
              child: Text(
                hasServices ? 'Top Services' : 'Top Selling Product',
                style: AppType.heading.copyWith(color: t.text),
              ),
            ),
          SoftSwitcher(
            child: KeyedSubtree(
              key: ValueKey('${view.name}-$_all'),
              child: view == _Insight.services
                  ? _ServiceBars(
                      services: widget.services,
                      all: _all,
                      onToggle: () => setState(() => _all = !_all),
                    )
                  : _ProductDonut(products: widget.products),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ranked bars: rank, name, bookings, share of all bookings, a bar that grows.
class _ServiceBars extends StatelessWidget {
  const _ServiceBars({
    required this.services,
    required this.all,
    required this.onToggle,
  });

  static const _limit = 5;

  final List<TopService> services;
  final bool all;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sorted = [...services]..sort((a, b) => b.count.compareTo(a.count));
    final total = sorted.fold<int>(0, (s, e) => s + e.count);
    final top = sorted.isEmpty ? 1 : sorted.first.count.clamp(1, 1 << 30);
    final rows = sorted.take(8).toList();
    final shown = all ? rows : rows.take(_limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpace.md),
          _BarRow(
            rank: i + 1,
            title: shown[i].name,
            count: shown[i].count,
            share: total == 0 ? 0 : shown[i].count / total,
            fraction: shown[i].count / top,
            color: i == 0 ? t.accent : t.accent.withValues(alpha: 0.62),
            delay: i,
          ),
        ],
        if (rows.length > _limit)
          Pressable(
            onTap: onToggle,
            minSize: 0,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpace.md),
              child: Center(
                child: Text(
                  all ? 'Show less' : 'Show ${rows.length - _limit} more',
                  style: AppType.label.copyWith(
                    color: t.accentText,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.rank,
    required this.title,
    required this.count,
    required this.share,
    required this.fraction,
    required this.color,
    required this.delay,
  });

  final int rank;
  final String title;
  final int count;
  final double share;
  final double fraction;
  final Color color;
  final int delay;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final pct = '${(share * 100).round()}%';
    return Semantics(
      label:
          '$rank, $title, $count ${count == 1 ? 'booking' : 'bookings'}, $pct',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank == 1
                      ? t.accent.withValues(alpha: 0.2)
                      : t.border.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: AppType.label.copyWith(
                    color: rank == 1 ? t.accentText : t.textMuted,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(
                    color: t.text,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: AppType.bodyStrong.copyWith(color: t.text, fontSize: 14),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 38,
                child: Text(
                  pct,
                  textAlign: TextAlign.end,
                  style: AppType.caption.copyWith(color: t.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduce ? 1 : 0, end: 1),
                duration: reduce
                    ? Duration.zero
                    : Duration(milliseconds: 600 + 90 * delay),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: (fraction.clamp(0.03, 1.0)) * v,
                  minHeight: 8,
                  backgroundColor: t.border.withValues(alpha: 0.6),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A donut of units sold (top five, the rest as "Other") with a legend.
class _ProductDonut extends StatelessWidget {
  const _ProductDonut({required this.products});

  static const _slices = 5;

  final List<TopProduct> products;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final sorted = [...products]..sort((a, b) => b.sold.compareTo(a.sold));
    final total = sorted.fold<int>(0, (s, e) => s + e.sold);
    final palette = [t.accent, t.violet, t.info, t.success, t.warning];

    final entries = <(String, int, Color)>[
      for (var i = 0; i < sorted.length && i < _slices; i++)
        (sorted[i].name, sorted[i].sold, palette[i]),
    ];
    final other = sorted.skip(_slices).fold<int>(0, (s, e) => s + e.sold);
    if (other > 0) entries.add(('Other', other, t.textMuted));

    return Semantics(
      label:
          'Top selling products, $total sold: '
          '${entries.map((e) => '${e.$1} ${e.$2}').join(', ')}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 132,
            height: 132,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: reduce ? 1 : 0, end: 1),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => CustomPaint(
                painter: _DonutPainter(
                  values: [for (final e in entries) e.$2.toDouble()],
                  colors: [for (final e in entries) e.$3],
                  track: t.border.withValues(alpha: 0.5),
                  progress: v,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(total * v).round()}',
                        style: AppType.title.copyWith(
                          color: t.text,
                          fontSize: 24,
                        ),
                      ),
                      Text(
                        'sold',
                        style: AppType.caption.copyWith(color: t.textMuted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) const SizedBox(height: 9),
                  _LegendRow(
                    color: entries[i].$3,
                    name: entries[i].$1,
                    sold: entries[i].$2,
                    share: total == 0 ? 0 : entries[i].$2 / total,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.name,
    required this.sold,
    required this.share,
  });

  final Color color;
  final String name;
  final int sold;
  final double share;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(color: t.text, fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$sold',
          style: AppType.bodyStrong.copyWith(color: t.text, fontSize: 13),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 34,
          child: Text(
            '${(share * 100).round()}%',
            textAlign: TextAlign.end,
            style: AppType.caption.copyWith(color: t.textMuted, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.track,
    required this.progress,
  });

  final List<double> values;
  final List<Color> colors;
  final Color track;

  /// 0..1: how much of the full circle is drawn (the sweep-in).
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);

    final total = values.fold<double>(0, (s, v) => s + v);
    if (total <= 0) return;
    final gap = values.length > 1 ? 0.045 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final full = values[i] / total * math.pi * 2;
      final sweep = math.max(0.0, full * progress - gap);
      if (sweep > 0) {
        canvas.drawArc(
          rect,
          start + gap / 2,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.butt
            ..color = colors[i],
        );
      }
      start += full * progress;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress ||
      old.track != track ||
      !_same(old.values, values) ||
      !_sameColors(old.colors, colors);

  static bool _same(List<double> a, List<double> b) =>
      a.length == b.length &&
      !List.generate(a.length, (i) => a[i] != b[i]).contains(true);

  static bool _sameColors(List<Color> a, List<Color> b) =>
      a.length == b.length &&
      !List.generate(a.length, (i) => a[i] != b[i]).contains(true);
}
