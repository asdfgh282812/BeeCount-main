import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/report/report_aggregator.dart';
import '../../../styles/tokens.dart';
import '../../../widgets/analytics/category_rank_row.dart';
import '../../../widgets/biz/biz.dart';
import '../../../widgets/charts/category_pie_chart.dart'
    show kCategoryChartColors;
import '../../../widgets/statistics/report_colors.dart';
import '../../../widgets/statistics/report_tx_row.dart';
import '../report_transactions_page.dart';
import '../report_view.dart';
import 'dimension_tab.dart';

/// 「總覽」分頁:收支結餘、主要支出類別、TOP 3 支出、商家統計。
class ReportOverviewTab extends ConsumerWidget {
  final ReportView view;
  const ReportOverviewTab({super.key, required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = view.agg.summary();
    final cats = view.agg.categoryHierarchy('expense');
    final top3 = view.agg.rankedTransactions('expense').take(3).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, reportBottomPadding(context)),
      children: [
        _SummaryCard(summary: s),
        if (s.txCount == 0)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: AppEmpty(text: l10n.commonEmpty),
          )
        else ...[
          if (cats.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(l10n.reportTopCategories, style: BeeTextTokens.title(context)),
            const SizedBox(height: 4),
            for (final (i, c) in cats.take(5).indexed)
              CategoryRankRow(
                categoryId: c.id,
                category: c.category,
                name: c.name,
                value: c.total,
                percent: s.expense == 0 ? 0 : c.total / s.expense,
                color: kCategoryChartColors[i % kCategoryChartColors.length],
                amountColor: reportFlowColor(context, ref, ReportFlow.expense),
                start: view.period.start,
                end: view.period.end,
                scope: 'month',
                selMonth: view.period.start,
                periodLabel: view.periodLabel,
                onOpenDetail: view.filtered
                    ? (id, name) => openReportCategoryDrilldown(context, view,
                        type: 'expense', categoryId: id, name: name)
                    : null,
                subCategories: c.subCategories,
              ),
          ],
          if (top3.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(l10n.reportTopExpenses, style: BeeTextTokens.title(context)),
            const SizedBox(height: 4),
            for (final (i, r) in top3.indexed)
              ReportTxRow(
                  view: r.view,
                  amount: r.amount,
                  rank: i + 1,
                  amountColor:
                      reportFlowColor(context, ref, ReportFlow.expense)),
          ],
          const SizedBox(height: 20),
          Text(l10n.reportTopMerchants, style: BeeTextTokens.title(context)),
          const SizedBox(height: 4),
          DimensionRankList(
            view: view,
            dimension: ReportDimension.merchant,
            flow: ReportFlow.expense,
            limit: 5,
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends ConsumerWidget {
  final ReportSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    Widget cell(String label, double v, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: BeeTextTokens.label(context)),
              const SizedBox(height: 4),
              AmountText(
                value: v,
                signed: false,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              cell(l10n.homeExpense, summary.expense,
                  reportFlowColor(context, ref, ReportFlow.expense)),
              cell(l10n.homeIncome, summary.income,
                  reportFlowColor(context, ref, ReportFlow.income)),
              cell(l10n.homeBalance, summary.balance,
                  reportBalanceColor(context, ref, summary.balance)),
            ],
          ),
          const SizedBox(height: 8),
          Text(l10n.reportTxCount(summary.txCount),
              style: TextStyle(
                  fontSize: 12, color: BeeTokens.textTertiary(context))),
        ],
      ),
    );
  }
}
