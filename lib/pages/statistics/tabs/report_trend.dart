import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/report/report_period.dart';
import '../../../providers.dart';
import '../../../services/report/report_aggregator.dart';
import '../../../styles/tokens.dart';
import '../../../utils/month_range.dart';
import '../../../widgets/charts/line_chart.dart';
import '../report_view.dart';

/// 趨勢圖資料:把 [ReportAggregator.series] 轉成 `LineChart` 要的值/標籤,
/// 並算出平均值(分母 = 區間內已發生的桶數,含零值桶,同舊洞察頁
/// `computeSeriesAverage` 的口徑)。
class ReportTrendData {
  final List<ReportSeriesPoint> points;
  final List<double> values;
  final List<String> labels;
  final int? highlightIndex;
  final double average;

  /// 給 `AnalyticsSummary.scope`:決定平均值文案是日均/月均/平均值。
  final String summaryScope;

  const ReportTrendData({
    required this.points,
    required this.values,
    required this.labels,
    required this.highlightIndex,
    required this.average,
    required this.summaryScope,
  });

  static ReportTrendData build(
      BuildContext context, ReportView v, String type) {
    final l10n = AppLocalizations.of(context);
    final g = v.period.granularity;
    final points = v.agg.series(
      type: type,
      granularity: g,
      start: v.period.start,
      end: v.period.end,
      monthStartDay: v.monthStartDay,
      openStart: v.period.openStart,
    );
    final values = [for (final p in points) p.value];
    final sameMonth = points.isEmpty ||
        points.every((p) =>
            p.bucket.year == points.first.bucket.year &&
            p.bucket.month == points.first.bucket.month);
    final sameYear = points.isEmpty ||
        points.every((p) => p.bucket.year == points.first.bucket.year);
    final labels = <String>[
      for (final p in points)
        switch (g) {
          ReportGranularity.day =>
            sameMonth ? '${p.bucket.day}' : '${p.bucket.month}/${p.bucket.day}',
          ReportGranularity.month => sameYear
              ? l10n.homeMonth(p.bucket.month.toString().padLeft(2, '0'))
              : '${p.bucket.year % 100}/${p.bucket.month}',
          ReportGranularity.year => '${p.bucket.year}',
        },
    ];
    int? highlight;
    final now = DateTime.now();
    final todayBucket = switch (g) {
      ReportGranularity.day => DateTime(now.year, now.month, now.day),
      ReportGranularity.month => labelForDate(now, v.monthStartDay),
      ReportGranularity.year =>
        DateTime(labelForDate(now, v.monthStartDay).year, 1, 1),
    };
    final idx = points.indexWhere((p) => p.bucket == todayBucket);
    if (idx >= 0 && g == ReportGranularity.day) {
      highlight = idx;
      labels[idx] = l10n.analyticsToday;
    }
    final total = values.fold<double>(0, (a, b) => a + b);
    return ReportTrendData(
      points: points,
      values: values,
      labels: labels,
      highlightIndex: highlight,
      average: values.isEmpty ? 0 : total / values.length,
      summaryScope: switch (g) {
        ReportGranularity.day => 'month',
        ReportGranularity.month => 'year',
        ReportGranularity.year => 'all',
      },
    );
  }
}

class ReportTrendChart extends ConsumerWidget {
  final ReportTrendData data;
  final ReportView view;
  final bool showHint;
  final VoidCallback? onCloseHint;
  final ValueChanged<int>? onPointTap;
  final double height;

  const ReportTrendChart({
    super.key,
    required this.data,
    required this.view,
    this.showHint = false,
    this.onCloseHint,
    this.onPointTap,
    this.height = 240,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (data.values.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: height,
      child: LineChart(
        values: data.values,
        xLabels: data.labels,
        highlightIndex: data.highlightIndex,
        hideAmounts: ref.watch(hideAmountsProvider),
        themeColor: Theme.of(context).colorScheme.primary,
        lineWidth: BeeChartTokens.lineWidth,
        dotRadius: BeeChartTokens.dotRadius,
        cornerRadius: BeeChartTokens.cornerRadius,
        xLabelFontSize: BeeChartTokens.xLabelFontSize,
        yLabelFontSize: BeeChartTokens.yLabelFontSize,
        onSwipeLeft: () => view.onNext?.call(),
        onSwipeRight: () => view.onPrev?.call(),
        onPointTap: onPointTap,
        showHint: showHint,
        hintText: AppLocalizations.of(context).analyticsSwipeHint,
        onCloseHint: onCloseHint,
        whiteBg: !BeeTokens.isDark(context),
        isDark: BeeTokens.isDark(context),
        showGrid: false,
        showDots: true,
        annotate: data.values.length <= 40,
      ),
    );
  }
}
