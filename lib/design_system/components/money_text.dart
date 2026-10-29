import 'package:flutter/material.dart';

import '../../core/utils/money.dart';
import '../tokens/typography.dart';

/// Money with tabular figures; the cents can be set smaller (hero totals).
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.money, {
    super.key,
    this.style,
    this.smallCents = false,
    this.color,
  });

  final Money money;
  final TextStyle? style;
  final bool smallCents;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? AppType.money).copyWith(
      color: color ?? style?.color ?? DefaultTextStyle.of(context).style.color,
    );
    if (!smallCents) return Text(money.format(), style: base);
    final whole = money.format(hideZeroCents: false);
    final dot = whole.lastIndexOf('.');
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: whole.substring(0, dot)),
          TextSpan(
            text: whole.substring(dot),
            style: base.copyWith(fontSize: (base.fontSize ?? 16) * 0.6),
          ),
        ],
      ),
    );
  }
}

/// Number that counts up once when it first appears (KPI tiles).
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.builder,
    this.duration = const Duration(milliseconds: 1200),
    this.style,
  });

  /// Overrides the default KPI number style.
  final TextStyle? style;
  final double value;
  final String Function(double) builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? value : 0, end: value),
      duration: reduce ? Duration.zero : duration,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(
        builder(v),
        style: (style ?? AppType.kpiNumber).copyWith(
          color: style?.color ?? DefaultTextStyle.of(context).style.color,
        ),
      ),
    );
  }
}
