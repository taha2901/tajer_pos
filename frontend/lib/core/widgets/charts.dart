import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../format.dart';

/// Single-series bar chart (title names the series, so no legend).
/// Thin bars, rounded data-ends, recessive grid, tooltip on every bar.
class SimpleBarChart extends StatelessWidget {
  const SimpleBarChart({
    super.key,
    required this.labels,
    required this.values,
    this.color,
    this.height = 180,
    this.secondValues,
    this.secondColor,
    this.valueLabel = 'القيمة',
    this.secondLabel = '',
  });

  final List<String> labels;
  final List<double> values;
  final Color? color;
  final double height;

  /// Optional second series (grouped) — callers must show a legend.
  final List<double>? secondValues;
  final Color? secondColor;
  final String valueLabel;
  final String secondLabel;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final c1 = color ?? context.colors.primary;
    final c2 = secondColor ?? pal.muted;
    final all = [...values, ...?secondValues];
    final maxV = all.isEmpty ? 0.0 : all.reduce(max);
    final top = maxV <= 0 ? 10.0 : _niceCeil(maxV);
    final grouped = secondValues != null;
    final n = values.length;
    final barWidth = (n > 20 ? 5.0 : n > 10 ? 8.0 : 14.0) / (grouped ? 1.4 : 1);
    final labelEvery = n > 14 ? (n / 7).ceil() : 1;
    const radius = BorderRadius.vertical(top: Radius.circular(4));

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: top,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: top / 4,
            getDrawingHorizontalLine: (_) => FlLine(color: pal.border, strokeWidth: 1, dashArray: const [3, 4]),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: top / 4,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(Fmt.compact(v), style: context.text.labelSmall?.copyWith(color: pal.muted, fontSize: 10)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= labels.length || i % labelEvery != 0) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(labels[i], style: context.text.labelSmall?.copyWith(color: pal.muted, fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => context.colors.inverseSurface,
              tooltipBorderRadius: BorderRadius.circular(8),
              getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                '${labels[group.x]}\n${grouped ? (rodIndex == 0 ? valueLabel : secondLabel) : valueLabel}: ${Fmt.money(rod.toY)}',
                TextStyle(color: context.colors.onInverseSurface, fontFamily: AppTheme.font, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: [
                  BarChartRodData(toY: max(0, values[i]), color: c1, width: barWidth, borderRadius: radius),
                  if (grouped) BarChartRodData(toY: max(0, secondValues![i]), color: c2, width: barWidth, borderRadius: radius),
                ],
              ),
          ],
        ),
      ),
    );
  }

  static double _niceCeil(double v) {
    final exp = pow(10, (log(v) / ln10).floor()).toDouble();
    final f = v / exp;
    final nice = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10;
    return nice * exp;
  }
}

/// Horizontal ranked bars (top-N lists) — single hue, value as text.
class RankedBars extends StatelessWidget {
  const RankedBars({super.key, required this.items, this.color, this.valueText, this.onTap});
  final List<(String label, double value, String caption)> items;
  final Color? color;
  final String Function(double value)? valueText;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final c = color ?? context.colors.primary;
    final maxV = items.isEmpty ? 1.0 : items.map((e) => e.$2).reduce(max);
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          InkWell(
            onTap: onTap == null ? null : () => onTap!(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(items[i].$1, style: context.text.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Text(valueText?.call(items[i].$2) ?? Fmt.money(items[i].$2), style: context.text.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: maxV <= 0 ? 0 : (items[i].$2 / maxV).clamp(0, 1).toDouble(),
                            minHeight: 6,
                            color: c,
                            backgroundColor: pal.subtle,
                          ),
                        ),
                      ),
                      if (items[i].$3.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(items[i].$3, style: context.text.labelSmall?.copyWith(color: pal.muted)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot(this.label, this.color, {super.key});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: context.text.labelSmall),
        ],
      );
}
