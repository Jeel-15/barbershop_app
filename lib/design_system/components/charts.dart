import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../tokens/app_tokens.dart';
import '../tokens/colors.dart';
import '../tokens/typography.dart';

class BarDatum {
  const BarDatum(this.label, this.value);

  final String label;
  final double value;
}

/// Simple vertical bars; one bar can be highlighted in gold.
class AppBarChart extends StatelessWidget {
  const AppBarChart({
    super.key,
    required this.data,
    this.highlight,
    this.height = 150,
    this.valueFormat,
  });

  final List<BarDatum> data;
  final int? highlight;
  final double height;
  final String Function(double)? valueFormat;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final maxY = data.fold<double>(0, (m, d) => d.value > m ? d.value : m);
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY == 0 ? 1 : maxY * 1.15,
          alignment: BarChartAlignment.spaceBetween,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, _) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    data[v.toInt()].label,
                    style: AppType.caption.copyWith(
                      fontSize: 10.5,
                      color: t.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => t.surfaceRaised,
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                valueFormat?.call(rod.toY) ?? rod.toY.toStringAsFixed(0),
                AppType.label.copyWith(color: t.text),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].value,
                    width: 14,
                    borderRadius: BorderRadius.circular(6),
                    gradient: i == highlight ? AppColors.goldGradient : null,
                    color: i == highlight
                        ? null
                        : t.textMuted.withValues(alpha: 0.35),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }
}

class DonutSlice {
  const DonutSlice(this.label, this.value, this.color);

  final String label;
  final double value;
  final Color color;
}

/// Ring chart with a centre label (payment methods, commission vs tips).
class AppDonutChart extends StatelessWidget {
  const AppDonutChart({
    super.key,
    required this.slices,
    this.centerTop,
    this.centerBottom,
    this.size = 180,
  });

  final List<DonutSlice> slices;
  final String? centerTop;
  final String? centerBottom;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 3,
              centerSpaceRadius: size * 0.32,
              startDegreeOffset: -90,
              sections: [
                for (final s in slices)
                  PieChartSectionData(
                    value: s.value <= 0 ? 0.0001 : s.value,
                    color: s.color,
                    radius: size * 0.16,
                    showTitle: false,
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 500),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (centerTop != null)
                Text(
                  centerTop!,
                  style: AppType.kpiNumber.copyWith(
                    fontSize: 22,
                    color: t.text,
                  ),
                ),
              if (centerBottom != null)
                Text(
                  centerBottom!,
                  style: AppType.caption.copyWith(color: t.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
