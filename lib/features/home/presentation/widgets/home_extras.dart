import 'package:barbershop_app/design_system/design_system.dart';
import 'package:barbershop_app/features/home/domain/dashboard.dart';
import 'package:flutter/material.dart';

enum _Insight { services, products }

/// Top services and top selling products in one card: a switch between them
/// instead of two cards, the best three shown and the rest one tap away.
///
/// Services are ranked by bookings (the web shows service + bookings; the money
/// column is left out on purpose: the web computes it with a formula that can
/// double-count).
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

    final rows = view == _Insight.services
        ? ([...widget.services]..sort((a, b) => b.count.compareTo(a.count)))
              .take(8)
              .map(
                (s) => (
                  s.name,
                  s.count,
                  '${s.count} ${s.count == 1 ? 'booking' : 'bookings'}',
                ),
              )
              .toList()
        : ([...widget.products]..sort((a, b) => b.sold.compareTo(a.sold)))
              .take(8)
              .map((p) => (p.name, p.sold, '${p.sold} sold'))
              .toList();
    final shown = _all ? rows : rows.take(3).toList();
    final max = rows.isEmpty ? 1 : rows.first.$2.clamp(1, 1 << 30);

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
            const SizedBox(height: AppSpace.md),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Text(
                hasServices ? 'Top Services' : 'Top Selling Product',
                style: AppType.heading.copyWith(color: t.text),
              ),
            ),
          SoftSwitcher(
            child: Column(
              key: ValueKey('${view.name}-$_all'),
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpace.sm + 2),
                  _BarRow(
                    rank: i + 1,
                    title: shown[i].$1,
                    trailing: shown[i].$3,
                    fraction: shown[i].$2 / max,
                    color: t.accent,
                  ),
                ],
              ],
            ),
          ),
          if (rows.length > 3)
            Pressable(
              onTap: () => setState(() => _all = !_all),
              minSize: 0,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Center(
                  child: Text(
                    _all ? 'Show less' : 'Show ${rows.length - 3} more',
                    style: AppType.label.copyWith(
                      color: t.accentText,
                      fontSize: 13,
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

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.title,
    required this.trailing,
    required this.fraction,
    required this.color,
    required this.rank,
  });

  final int rank;
  final String title;
  final String trailing;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: AppType.label.copyWith(color: t.textMuted),
              ),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.bodyStrong.copyWith(color: t.text, fontSize: 14),
              ),
            ),
            Text(
              trailing,
              style: AppType.caption.copyWith(color: t.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction.clamp(0.03, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 5,
                backgroundColor: t.border,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
