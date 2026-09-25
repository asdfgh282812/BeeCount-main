import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../../services/report/report_aggregator.dart';
import '../../../styles/tokens.dart';
import '../../../widgets/analytics/analytics_summary.dart';
import '../../../widgets/analytics/category_rank_row.dart';
import '../../../widgets/charts/category_pie_chart.dart';
import '../../../widgets/ui/capsule_switcher.dart';
import '../../../widgets/biz/biz.dart';
import '../../../widgets/statistics/report_colors.dart';
import '../report_transactions_page.dart';
import '../report_view.dart';
import 'report_trend.dart';

/// 「類別」分頁:原洞察頁內容(圓餅 + 分類排行 + 趨勢),期間改由報表決定,
/// 不再有自己的月/年/全部切換。
class ReportCategoryTab extends ConsumerStatefulWidget {
  final ReportView view;
  const ReportCategoryTab({super.key, required this.view});

  @override
  ConsumerState<ReportCategoryTab> createState() => _ReportCategoryTabState();
}

class _ReportCategoryTabState extends ConsumerState<ReportCategoryTab>
    with AutomaticKeepAliveClientMixin {
  String _type = 'expense'; // expense | income | balance
  bool _trendExpanded = false;
  bool _localChartHintDismissed = false;

  @override
  bool get wantKeepAlive => true;

  void _openFiltered(int categoryId, String name, List<int> childIds) =>
      openReportCategoryDrilldown(context, widget.view,
          type: _type, categoryId: categoryId, name: name, childIds: childIds);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final v = widget.view;
    final summary = v.agg.summary();
    final cats = _type == 'balance'
        ? const <ReportCategoryItem>[]
        : v.agg.categoryHierarchy(_type);
    final sum = _type == 'balance'
        ? summary.balance
        : (_type == 'income' ? summary.income : summary.expense);
    // 圓餅只畫正值分類:退款沖銷可能讓某分類淨額 ≤ 0,扇形角度要用正值
    // 合計算,中間顯示的總額仍是淨額。
    final pieSum =
        cats.fold<double>(0, (a, c) => c.total > 0 ? a + c.total : a);
    final count = _type == 'balance'
        ? summary.incomeCount + summary.expenseCount
        : (_type == 'income' ? summary.incomeCount : summary.expenseCount);

    final chartHintDismissed =
        (ref.watch(analyticsChartHintDismissedProvider).asData?.value ??
                false) ||
            _localChartHintDismissed;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, reportBottomPadding(context)),
      children: [
        CapsuleSwitcher<String>(
          selectedValue: _type,
          height: 34,
          options: [
            CapsuleOption(value: 'expense', label: l10n.homeExpense),
            CapsuleOption(value: 'income', label: l10n.homeIncome),
            CapsuleOption(value: 'balance', label: l10n.homeBalance),
          ],
          onChanged: (t) => setState(() => _type = t),
        ),
        const SizedBox(height: 16),
        if (count == 0 && sum == 0)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: AppEmpty(text: l10n.commonEmpty),
          )
        else ...[
          if (_type != 'balance') ...[
            Text(l10n.analyticsCategoryRanking,
                style: BeeTextTokens.title(context)),
            const SizedBox(height: 8),
            if (cats.isNotEmpty && pieSum > 0)
              CategoryPieChart(
                data: cats,
                sum: pieSum,
                centerTotal: sum,
                centerColor: reportFlowColor(context, ref, _type),
                start: v.period.start,
                end: v.period.end,
                scope: 'month',
                selMonth: v.period.start,
                periodLabel: v.periodLabel,
                onOpenDetail: v.filtered ? _openFiltered : null,
              ),
            const SizedBox(height: 12),
            for (final (i, c) in cats.indexed)
              CategoryRankRow(
                categoryId: c.id,
                category: c.category,
                name: c.name,
                value: c.total,
                percent: sum == 0 ? 0 : c.total / sum,
                color: kCategoryChartColors[i % kCategoryChartColors.length],
                amountColor: reportFlowColor(context, ref, _type),
                start: v.period.start,
                end: v.period.end,
                scope: 'month',
                selMonth: v.period.start,
                periodLabel: v.periodLabel,
                onOpenDetail: v.filtered
                    ? (id, name) => _openFiltered(id, name, const [])
                    : null,
                subCategories: c.subCategories,
              ),
            const SizedBox(height: 20),
          ],
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _trendExpanded = !_trendExpanded),
            child: Row(
              children: [
                Text(l10n.analyticsTrendTitle,
                    style: BeeTextTokens.title(context)),
                const Spacer(),
                Icon(
                  _trendExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: BeeTokens.textSecondary(context),
                ),
              ],
            ),
          ),
          if (_trendExpanded) ...[
            const SizedBox(height: 8),
            Builder(builder: (context) {
              final trend = ReportTrendData.build(context, v, _type);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnalyticsSummary(
                    scope: trend.summaryScope,
                    isExpense: _type == 'expense',
                    isBalance: _type == 'balance',
                    total: sum,
                    avg: trend.average,
                  ),
                  const SizedBox(height: 12),
                  ReportTrendChart(
                    data: trend,
                    view: v,
                    showHint: !chartHintDismissed &&
                        (v.onPrev != null || v.onNext != null),
                    onCloseHint: () async {
                      await ref
                          .read(analyticsHintsSetterProvider)
                          .dismissChart();
                      if (mounted) {
                        setState(() => _localChartHintDismissed = true);
                      }
                    },
                  ),
                ],
              );
            }),
          ],
        ],
      ],
    );
  }
}
