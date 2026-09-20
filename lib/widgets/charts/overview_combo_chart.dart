import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/overview_chart_utils.dart';

/// 資產管理頁「走勢」的 Moze 風格互動組合圖：長條（收入/支出）+ 折線（淨資產），
/// 可切換 日/週/月/年 統計區間，可拖曳/點擊查看某一天的數字。
///
/// 內嵌卡片版與全螢幕版（[AccountOverviewChartPage]）共用同一個元件、同一個
/// [accountOverviewChartSeriesProvider]：使用者可以直接在卡片上點/拖曳選點，
/// 不會因為點了圖表就跳走；要看放大版走全螢幕頁,只能靠頁首的「展開」圖示。
/// 兩邊統計區間切換按鈕與粒度狀態都各自獨立（每個元件實例自帶
/// [OverviewGranularity] state），因為兩者是各自獨立的 widget 實例。
class OverviewComboChart extends ConsumerStatefulWidget {
  const OverviewComboChart({super.key});

  @override
  ConsumerState<OverviewComboChart> createState() => _OverviewComboChartState();
}

class _OverviewComboChartState extends ConsumerState<OverviewComboChart> {
  OverviewGranularity _granularity = OverviewGranularity.day;
  int? _selectedIndex;

  String _granularityLabel(AppLocalizations l10n, OverviewGranularity g) {
    switch (g) {
      case OverviewGranularity.day:
        return l10n.accountOverviewChartByDay;
      case OverviewGranularity.week:
        return l10n.accountOverviewChartByWeek;
      case OverviewGranularity.month:
        return l10n.accountOverviewChartByMonth;
      case OverviewGranularity.year:
        return l10n.accountOverviewChartByYear;
    }
  }

  Future<void> _pickGranularity() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<OverviewGranularity>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BeeTokens.surfaceSheet(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: BeeTokens.divider(bctx),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.accountOverviewChartGranularityTitle,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: BeeTokens.textPrimary(bctx),
              ),
            ),
            const SizedBox(height: 8),
            for (final g in OverviewGranularity.values)
              ListTile(
                title: Text(
                  _granularityLabel(l10n, g),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight:
                        g == _granularity ? FontWeight.w600 : FontWeight.normal,
                    color: g == _granularity
                        ? ref.read(primaryColorProvider)
                        : BeeTokens.textPrimary(bctx),
                  ),
                ),
                onTap: () => Navigator.of(bctx).pop(g),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && picked != _granularity) {
      setState(() {
        _granularity = picked;
        _selectedIndex = null; // 切换粒度后重设为最新时间点
      });
    }
  }

  void _handleTouch(Offset local, Size size, int pointCount) {
    if (pointCount < 2) return;
    const leftPad = 12.0;
    const rightPad = 12.0;
    final dx = (size.width - leftPad - rightPad) / (pointCount - 1);
    final idx = dx <= 0
        ? 0
        : ((local.dx - leftPad) / dx).round().clamp(0, pointCount - 1);
    if (idx != _selectedIndex) {
      setState(() => _selectedIndex = idx);
    }
  }

  String _xLabel(OverviewChartPoint p) {
    final d = p.bucketStart;
    switch (_granularity) {
      case OverviewGranularity.day:
      case OverviewGranularity.week:
        return '${d.month}/${d.day}';
      case OverviewGranularity.month:
        return '${d.year % 100}/${d.month}';
      case OverviewGranularity.year:
        return '${d.year}';
    }
  }

  String _weekdayLabel(AppLocalizations l10n, DateTime d) {
    switch (d.weekday) {
      case DateTime.monday:
        return l10n.commonWeekdayMonday;
      case DateTime.tuesday:
        return l10n.commonWeekdayTuesday;
      case DateTime.wednesday:
        return l10n.commonWeekdayWednesday;
      case DateTime.thursday:
        return l10n.commonWeekdayThursday;
      case DateTime.friday:
        return l10n.commonWeekdayFriday;
      case DateTime.saturday:
        return l10n.commonWeekdaySaturday;
      case DateTime.sunday:
      default:
        return l10n.commonWeekdaySunday;
    }
  }

  String _dateLabel(AppLocalizations l10n, OverviewChartPoint p) {
    final d = p.bucketStart;
    switch (_granularity) {
      case OverviewGranularity.day:
        return '${d.year}/${d.month}/${d.day} ${_weekdayLabel(l10n, d)}';
      case OverviewGranularity.week:
        final end = d.add(const Duration(days: 6));
        return '${d.month}/${d.day} - ${end.month}/${end.day}';
      case OverviewGranularity.month:
        return '${d.year}/${d.month}';
      case OverviewGranularity.year:
        return '${d.year}';
    }
  }

  String _fmtSigned(double v, bool hide) {
    if (hide) return '****';
    final sign = v > 0 ? '+' : '';
    return '$sign${_fmtCompact(v)}';
  }

  String _fmtCompact(double v) {
    final av = v.abs();
    if (av >= 100000000) return '${(v / 100000000).toStringAsFixed(2)}亿';
    if (av >= 10000) return '${(v / 10000).toStringAsFixed(1)}w';
    if (av >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pointsAsync =
        ref.watch(accountOverviewChartSeriesProvider(_granularity));
    final hide = ref.watch(hideAmountsProvider);
    final primary = ref.watch(primaryColorProvider);
    final incomeColor = BeeTokens.incomeColor(context, ref);
    final expenseColor = BeeTokens.expenseColor(context, ref);

    return pointsAsync.when(
      skipLoadingOnReload: true,
      data: (points) {
        if (points.length < 2) {
          return Center(
            child: Text(l10n.commonEmpty,
                style: TextStyle(
                    fontSize: 12, color: BeeTokens.textTertiary(context))),
          );
        }
        final selected =
            (_selectedIndex ?? points.length - 1).clamp(0, points.length - 1);
        final point = points[selected];
        final net = point.income - point.expense;
        final netColor = net >= 0 ? incomeColor : expenseColor;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickGranularity,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _granularityLabel(l10n, _granularity),
                        style: TextStyle(
                            fontSize: 12,
                            color: BeeTokens.textSecondary(context),
                            fontWeight: FontWeight.w600),
                      ),
                      Icon(Icons.expand_more,
                          size: 16, color: BeeTokens.textSecondary(context)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) =>
                        _handleTouch(d.localPosition, size, points.length),
                    onPanStart: (d) =>
                        _handleTouch(d.localPosition, size, points.length),
                    onPanUpdate: (d) =>
                        _handleTouch(d.localPosition, size, points.length),
                    child: CustomPaint(
                      size: size,
                      painter: _OverviewComboPainter(
                        points: points,
                        xLabels: points.map(_xLabel).toList(),
                        selectedIndex: selected,
                        hideAmounts: hide,
                        incomeColor: incomeColor,
                        expenseColor: expenseColor,
                        lineColor: primary,
                        isDark: BeeTokens.isDark(context),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(_dateLabel(l10n, point),
                    style: TextStyle(
                        fontSize: 12, color: BeeTokens.textSecondary(context))),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: netColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(_fmtSigned(net, hide),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: netColor)),
              ],
            ),
          ],
        );
      },
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => Center(
        child: Text(l10n.commonError,
            style: TextStyle(
                fontSize: 12, color: BeeTokens.textTertiary(context))),
      ),
    );
  }
}

class _OverviewComboPainter extends CustomPainter {
  final List<OverviewChartPoint> points;
  final List<String> xLabels;
  final int selectedIndex;
  final bool hideAmounts;
  final Color incomeColor;
  final Color expenseColor;
  final Color lineColor;
  final bool isDark;

  _OverviewComboPainter({
    required this.points,
    required this.xLabels,
    required this.selectedIndex,
    required this.hideAmounts,
    required this.incomeColor,
    required this.expenseColor,
    required this.lineColor,
    required this.isDark,
  });

  Color get gridColor => BeeTokens.dividerStatic;
  Color get axisTextColor =>
      isDark ? Colors.white70 : BeeTokens.secondaryTextStatic;
  Color get highlightTextColor =>
      isDark ? Colors.white : BeeTokens.primaryTextStatic;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPad = 12.0;
    const rightPad = 12.0;
    const topPad = 30.0; // 给上方数值泡泡留空间
    const bottomPad = 18.0; // X 轴标签

    final n = points.length;
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = math.max(0.0, size.height - topPad - bottomPad);
    final dx = n > 1 ? chartWidth / (n - 1) : 0.0;
    double xFor(int i) => leftPad + dx * i;

    // 左轴（长条）：收入/支出，0 起算。
    final barMax = points.fold<double>(
        0, (m, p) => math.max(m, math.max(p.income, p.expense)));
    double barY(double v) =>
        topPad + chartHeight - (barMax <= 0 ? 0 : (v / barMax) * chartHeight);

    // 右轴（折线）：净资产，按 min/max 自动取格线。
    final netValues = points.map((p) => p.netWorth).toList();
    final netMax = netValues.reduce(math.max);
    final netMin = netValues.reduce(math.min);
    final netSpan = (netMax - netMin).abs();
    double lineY(double v) {
      if (netSpan == 0) return topPad + chartHeight / 2;
      final t = (v - netMin) / netSpan;
      return topPad + (1 - t) * chartHeight;
    }

    // 网格线
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const rows = 3;
    for (int i = 1; i <= rows; i++) {
      final y = topPad + chartHeight * i / (rows + 1);
      canvas.drawLine(
          Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
    }

    // 长条：每个时间点最多两根并排小长条，某类别为 0 时不画该长条。
    final barGroupWidth = (dx * 0.55).clamp(6.0, 24.0);
    final barWidth = (barGroupWidth / 2 - 1).clamp(2.0, 10.0);
    for (int i = 0; i < n; i++) {
      final cx = xFor(i);
      final p = points[i];
      if (p.income > 0) {
        final rect = Rect.fromLTRB(
            cx - barWidth - 1, barY(p.income), cx - 1, topPad + chartHeight);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect,
              topLeft: const Radius.circular(2),
              topRight: const Radius.circular(2)),
          Paint()..color = incomeColor,
        );
      }
      if (p.expense > 0) {
        final rect = Rect.fromLTRB(
            cx + 1, barY(p.expense), cx + 1 + barWidth, topPad + chartHeight);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect,
              topLeft: const Radius.circular(2),
              topRight: const Radius.circular(2)),
          Paint()..color = expenseColor,
        );
      }
    }

    // 折线：净资产，直线连接各点。
    final linePath = Path();
    for (int i = 0; i < n; i++) {
      final pt = Offset(xFor(i), lineY(points[i].netWorth));
      if (i == 0) {
        linePath.moveTo(pt.dx, pt.dy);
      } else {
        linePath.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..isAntiAlias = true,
    );

    // 选中点：竖直参考线 + 圆点 + 数值泡泡（边界自动内缩，避免超出画布）。
    if (selectedIndex >= 0 && selectedIndex < n) {
      final sx = xFor(selectedIndex);
      final sy = lineY(points[selectedIndex].netWorth);
      canvas.drawLine(
          Offset(sx, topPad),
          Offset(sx, topPad + chartHeight),
          Paint()
            ..color = gridColor
            ..strokeWidth = 1);
      canvas.drawCircle(Offset(sx, sy), 3.5, Paint()..color = lineColor);
      canvas.drawCircle(
          Offset(sx, sy),
          3.5,
          Paint()
            ..color = isDark ? Colors.black : Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);

      final label =
          hideAmounts ? '**' : _fmtCompact(points[selectedIndex].netWorth);
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      final bubbleW = tp.width + 16;
      const bubbleH = 22.0;
      final bx = (sx - bubbleW / 2)
          .clamp(0.0, math.max(0.0, size.width - bubbleW))
          .toDouble();
      final by = (sy - bubbleH - 8)
          .clamp(0.0, math.max(0.0, size.height - bubbleH))
          .toDouble();
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(bx, by, bubbleW, bubbleH), const Radius.circular(6)),
        Paint()..color = lineColor,
      );
      tp.paint(canvas, Offset(bx + 8, by + (bubbleH - tp.height) / 2));
    }

    // X 轴标签，间隔跳过避免拥挤，选中点加粗高亮。
    if (xLabels.isNotEmpty) {
      final baseStyle = TextStyle(fontSize: 10, color: axisTextColor);
      final hiStyle = TextStyle(
          fontSize: 10, color: highlightTextColor, fontWeight: FontWeight.w600);
      int step = (n / 6).ceil();
      if (step < 1) step = 1;
      for (int i = 0; i < n; i += step) {
        final tp = TextPainter(
          text: TextSpan(
              text: xLabels[i],
              style: i == selectedIndex ? hiStyle : baseStyle),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 60);
        final cx = xFor(i);
        final tx = (cx - tp.width / 2)
            .clamp(0.0, math.max(0.0, size.width - tp.width))
            .toDouble();
        tp.paint(canvas, Offset(tx, size.height - bottomPad + 4));
      }
    }
  }

  String _fmtCompact(double v) {
    final av = v.abs();
    if (av >= 10000) return '${(v / 10000).toStringAsFixed(1)}w';
    if (av >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _OverviewComboPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.hideAmounts != hideAmounts ||
        oldDelegate.isDark != isDark ||
        oldDelegate.lineColor != lineColor;
  }
}
