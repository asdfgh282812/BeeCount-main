import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../styles/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/category_utils.dart';
import '../../data/db.dart' as db;
import '../../pages/transaction/category_detail_page.dart';
import '../biz/biz.dart';

/// 分类调色板（12 色，覆盖常见分类数量）——同时给下方的
/// `CategoryRankRow` 排行清单使用(2026-09-13 使用者反馈:洞察页排行榜
/// 每一列的底线/进度条都是同一个主题色,没有像饼图一样按分类区分颜色)。
/// 两处都按「金额降序」排列后取相同的 index 对调色盘取模,确保同一个分类
/// 在饼图扇区和下方排行条目上颜色一致。
const kCategoryChartColors = <Color>[
  Color(0xFF5B8FF9), // 蓝
  Color(0xFF5AD8A6), // 绿
  Color(0xFFF6BD16), // 黄
  Color(0xFFE86452), // 红
  Color(0xFF6DC8EC), // 浅蓝
  Color(0xFF945FB9), // 紫
  Color(0xFFFF9845), // 橙
  Color(0xFF1E9493), // 青
  Color(0xFFFF99C3), // 粉
  Color(0xFF269A99), // 深青
  Color(0xFFBDD2FD), // 淡蓝
  Color(0xFFA0DC2C), // 黄绿
];

/// 分类饼图条目
typedef PieCategoryItem = ({
  int? id,
  String name,
  db.Category? category,
  double total,
  List<
      ({
        int id,
        db.Category category,
        String name,
        double total
      })> subCategories,
});

/// fl_chart 默认 startDegreeOffset = 0（3 点钟方向），顺时针增长，
/// 外部引线标签的角度换算必须跟这个约定保持一致，否则线会对不准扇区。
/// 环形粗细比例（section 半径 / 外半径），实际半径依容器宽度动态算出。
const double _kSectionRadiusRatio = 0.34;
const double _kElbowGap = 8; // 外缘到引线转折点的径向距离
const double _kHorizontalSeg = 14; // 转折点到标签文字的水平距离
const double _kLabelReserve = 70; // 给标签文字预留的水平宽度（含名称+百分比场景）
const double _kMinOuterRadius = 60;
const double _kMaxOuterRadius = 130;

/// 分类占比饼图（环形图 + 仿 Moze 风格的外部引线百分比标签）
class CategoryPieChart extends ConsumerStatefulWidget {
  final List<PieCategoryItem> data;
  final double sum;

  /// 统计区间信息：用于点击扇区跳转到该分类的交易明细页
  final DateTime start;
  final DateTime end;
  final String scope; // month | year | all
  final DateTime selMonth;

  /// 选中扇区回调，返回分类索引（-1 表示取消选中）
  final ValueChanged<int>? onSectionTap;

  const CategoryPieChart({
    super.key,
    required this.data,
    required this.sum,
    required this.start,
    required this.end,
    required this.scope,
    required this.selMonth,
    this.onSectionTap,
  });

  @override
  ConsumerState<CategoryPieChart> createState() => _CategoryPieChartState();
}

class _CategoryPieChartState extends ConsumerState<CategoryPieChart> {
  int _touchedIndex = -1;

  /// 最多显示的扇区数（超出合并为「其他」）
  static const _maxSlices = 8;

  @override
  void didUpdateWidget(CategoryPieChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _touchedIndex = -1;
    }
  }

  /// 将原始分类列表合并为 ≤ _maxSlices 条，多余归入「其他」
  List<({String name, double total, Color color, int originalIndex})>
      _buildSlices() {
    final sorted = List.generate(widget.data.length, (i) => i);
    sorted.sort((a, b) => widget.data[b].total.compareTo(widget.data[a].total));

    final slices =
        <({String name, double total, Color color, int originalIndex})>[];
    double otherTotal = 0;

    for (var i = 0; i < sorted.length; i++) {
      final idx = sorted[i];
      final item = widget.data[idx];
      if (item.total <= 0) continue;

      if (slices.length < _maxSlices) {
        slices.add((
          name: item.name,
          total: item.total,
          color: kCategoryChartColors[slices.length % kCategoryChartColors.length],
          originalIndex: idx,
        ));
      } else {
        otherTotal += item.total;
      }
    }

    if (otherTotal > 0) {
      slices.add((
        name: '_other_',
        total: otherTotal,
        color: BeeTokens.textTertiary(context),
        originalIndex: -1,
      ));
    }

    return slices;
  }

  String _currentPeriodLabel(BuildContext context) {
    switch (widget.scope) {
      case 'year':
        return '${widget.selMonth.year}';
      case 'all':
        return AppLocalizations.of(context).analyticsAllYears;
      default:
        return '${widget.selMonth.year}.${widget.selMonth.month.toString().padLeft(2, '0')}';
    }
  }

  /// 根据本地坐标算出命中的扇区索引（-1 表示落在圆心洞、外圈或扇区间隙等空白处）。
  /// 角度换算沿用 fl_chart 的约定：0°=3 点钟方向，顺时针增长。
  int _hitTestSlice({
    required Offset localPosition,
    required Offset center,
    required double centerSpaceRadius,
    required double outerRadius,
    required List<({double start, double sweep})> angles,
  }) {
    final v = localPosition - center;
    final r = v.distance;
    if (r <= centerSpaceRadius || r > outerRadius) return -1;

    var deg = math.atan2(v.dy, v.dx) * 180 / math.pi;
    if (deg < 0) deg += 360;

    for (var i = 0; i < angles.length; i++) {
      final a = angles[i];
      if (deg >= a.start && deg < a.start + a.sweep) return i;
    }
    return -1;
  }

  void _openCategoryDetail(int originalIndex) {
    if (originalIndex < 0 || originalIndex >= widget.data.length) return;
    final item = widget.data[originalIndex];
    if (item.id == null) return;
    final periodLabel =
        widget.scope != 'all' ? _currentPeriodLabel(context) : null;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CategoryDetailPage(
          categoryId: item.id!,
          categoryName: item.name,
          startDate: widget.scope != 'all' ? widget.start : null,
          endDate: widget.scope != 'all' ? widget.end : null,
          periodLabel: periodLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.isEmpty || widget.sum <= 0) {
      return const SizedBox.shrink();
    }

    final slices = _buildSlices();
    if (slices.isEmpty) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);

    // 选中扇区的信息（显示在环形中心）
    final hasSelection = _touchedIndex >= 0 && _touchedIndex < slices.length;
    final selectedSlice = hasSelection ? slices[_touchedIndex] : null;

    // 各扇区的起止角度（度），与 fl_chart 的 startDegreeOffset=0、顺时针一致
    final angles = <({double start, double sweep})>[];
    double cumulative = 0;
    for (final s in slices) {
      final sweep = s.total / widget.sum * 360;
      angles.add((start: cumulative, sweep: sweep));
      cumulative += sweep;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.maxWidth;
        final outerRadius =
            (boxWidth / 2 - _kElbowGap - _kHorizontalSeg - _kLabelReserve)
                .clamp(_kMinOuterRadius, _kMaxOuterRadius);
        final sectionRadius = outerRadius * _kSectionRadiusRatio;
        final centerSpaceRadius = outerRadius - sectionRadius;
        final chartBoxHeight = outerRadius * 2 + 70;
        final center = Offset(boxWidth / 2, chartBoxHeight / 2);
        final lineColor =
            BeeTokens.textTertiary(context).withValues(alpha: 0.5);

        // 不用 fl_chart 自带的 pieTouchData：它内部会注册自己的 tap/pan/
        // longPress 手势识别器参与手势竞技场，跟外层「左右滑动切换收支视角」
        // 的 GestureDetector 混在一起时命中并不稳定（实机上经常点了没反应）。
        // 改成用一个普通 GestureDetector 自己接手点击，行为更可预期。
        void handleTapDown(TapDownDetails details) {
          final hitIdx = _hitTestSlice(
            localPosition: details.localPosition,
            center: center,
            centerSpaceRadius: centerSpaceRadius,
            outerRadius: outerRadius,
            angles: angles,
          );
          if (hitIdx != _touchedIndex) {
            setState(() => _touchedIndex = hitIdx);
            widget.onSectionTap
                ?.call(hitIdx >= 0 ? slices[hitIdx].originalIndex : -1);
          }
        }

        void handleTapUp(TapUpDetails details) {
          final hitIdx = _hitTestSlice(
            localPosition: details.localPosition,
            center: center,
            centerSpaceRadius: centerSpaceRadius,
            outerRadius: outerRadius,
            angles: angles,
          );
          if (hitIdx >= 0 && hitIdx < slices.length) {
            _openCategoryDetail(slices[hitIdx].originalIndex);
          }
          if (_touchedIndex != -1) {
            setState(() => _touchedIndex = -1);
            widget.onSectionTap?.call(-1);
          }
        }

        void handleTapCancel() {
          if (_touchedIndex != -1) {
            setState(() => _touchedIndex = -1);
            widget.onSectionTap?.call(-1);
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: handleTapDown,
          onTapUp: handleTapUp,
          onTapCancel: handleTapCancel,
          child: SizedBox(
            height: chartBoxHeight,
            width: boxWidth,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: centerSpaceRadius,
                    sections: List.generate(slices.length, (i) {
                      final s = slices[i];
                      final pct = s.total / widget.sum * 100;
                      final isTouched = i == _touchedIndex;
                      // 扇区够大才在圆环内直接写分类名，太小则靠外部引线标签补上名称
                      final showInnerName = pct >= 10;
                      final displayName = s.name == '_other_'
                          ? l10n.commonOther
                          : CategoryUtils.getDisplayName(s.name, context);
                      return PieChartSectionData(
                        color: s.color,
                        value: s.total,
                        title: showInnerName ? displayName : '',
                        radius: isTouched ? sectionRadius + 6 : sectionRadius,
                        titleStyle: TextStyle(
                          fontSize: isTouched ? 13 : 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      );
                    }),
                  ),
                ),
                CustomPaint(
                  size: Size(boxWidth, chartBoxHeight),
                  painter: _LeaderLinePainter(
                    angles: angles,
                    center: center,
                    outerRadius: outerRadius,
                    lineColor: lineColor,
                  ),
                ),
                for (var i = 0; i < slices.length; i++)
                  _buildPercentLabel(
                    context: context,
                    boxWidth: boxWidth,
                    center: center,
                    outerRadius: outerRadius,
                    angle: angles[i],
                    slice: slices[i],
                    l10n: l10n,
                  ),
                // 环形中心：选中时显示分类名称，未选中时只显示总额数字
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selectedSlice != null) ...[
                      Text(
                        selectedSlice.name == '_other_'
                            ? l10n.commonOther
                            : CategoryUtils.getDisplayName(
                                selectedSlice.name, context),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: BeeTokens.textTertiary(context),
                              fontSize: 11,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                    ],
                    AmountText(
                      value: selectedSlice?.total ?? widget.sum,
                      signed: false,
                      decimals: 0,
                      style: TextStyle(
                        fontSize: selectedSlice != null ? 16 : 22,
                        fontWeight: FontWeight.w700,
                        color: BeeTokens.textPrimary(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 扇区外部的百分比标签（仿 Moze：径向引线 + 水平段，靠左右两侧对齐）。
  /// 圆环内没写分类名的扇区，会在百分比旁一并补上分类名。
  Widget _buildPercentLabel({
    required BuildContext context,
    required double boxWidth,
    required Offset center,
    required double outerRadius,
    required ({double start, double sweep}) angle,
    required ({
      String name,
      double total,
      Color color,
      int originalIndex
    }) slice,
    required AppLocalizations l10n,
  }) {
    final midRad = (angle.start + angle.sweep / 2) * math.pi / 180;
    final dir = Offset(math.cos(midRad), math.sin(midRad));
    final elbow = center + dir * (outerRadius + _kElbowGap);
    final isRight = dir.dx >= 0;
    final lineEnd =
        elbow + Offset(isRight ? _kHorizontalSeg : -_kHorizontalSeg, 0);
    final pct = slice.total / widget.sum * 100;
    final pctText = '${pct.toStringAsFixed(pct < 10 ? 1 : 0)}%';
    final showInnerName = pct >= 10;
    final displayName = slice.name == '_other_'
        ? l10n.commonOther
        : CategoryUtils.getDisplayName(slice.name, context);
    final text = showInnerName ? pctText : '$displayName $pctText';

    return Positioned(
      top: lineEnd.dy - 8,
      left: isRight ? lineEnd.dx + 4 : null,
      right: isRight ? null : boxWidth - lineEnd.dx + 4,
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: BeeTokens.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 绘制每个扇区的外部引线：从环形外缘径向延伸一小段，再水平拐向左右两侧。
class _LeaderLinePainter extends CustomPainter {
  final List<({double start, double sweep})> angles;
  final Offset center;
  final double outerRadius;
  final Color lineColor;

  _LeaderLinePainter({
    required this.angles,
    required this.center,
    required this.outerRadius,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (final angle in angles) {
      final midRad = (angle.start + angle.sweep / 2) * math.pi / 180;
      final dir = Offset(math.cos(midRad), math.sin(midRad));
      final start = center + dir * outerRadius;
      final elbow = center + dir * (outerRadius + _kElbowGap);
      final isRight = dir.dx >= 0;
      final end =
          elbow + Offset(isRight ? _kHorizontalSeg : -_kHorizontalSeg, 0);

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..lineTo(elbow.dx, elbow.dy)
        ..lineTo(end.dx, end.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LeaderLinePainter oldDelegate) {
    return oldDelegate.angles != angles ||
        oldDelegate.center != center ||
        oldDelegate.outerRadius != outerRadius ||
        oldDelegate.lineColor != lineColor;
  }
}
