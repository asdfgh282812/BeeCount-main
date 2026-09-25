import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/report/report_dataset.dart';
import '../../providers.dart';
import '../../services/report/report_aggregator.dart';
import '../../styles/tokens.dart';
import '../../widgets/biz/biz.dart';
import '../../widgets/statistics/report_colors.dart';
import '../../widgets/ui/ui.dart';
import 'report_view.dart';

/// 統計報表的下鑽列表:同一個 [query](期間 + 報表篩選)下,再以 [where]
/// 挑出某個維度值的交易。跟 `CategoryDetailPage` 的差別是會套用報表篩選,
/// 且任何維度(帳戶/商家/標籤…)都能用。
///
/// [flow](支出/收入/轉帳/回饋金)是從哪個切換進來的:[where] 已經只挑該
/// flow 的 legs,這裡據此顯示單一合計。支出下鑽只會列支出(含扣在支出上的
/// 退款單),不會混進收入。
class ReportTransactionsPage extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final ReportQuery query;
  final bool Function(ReportEntry e) where;
  final String flow;

  /// flow = 回饋金時的 `{交易 id: 估算回饋金}`。
  final Map<int, double> rewards;

  const ReportTransactionsPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.query,
    required this.where,
    this.flow = ReportFlow.expense,
    this.rewards = const {},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(reportDatasetProvider(query));
    return Scaffold(
      body: Column(
        children: [
          PrimaryHeader(
            title: title,
            subtitle: subtitle,
            showBack: true,
            compact: true,
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('${l10n.commonError}: $e')),
              data: (ds) {
                final agg = ReportAggregator(ReportDataset(
                  entries: ds.entries.where(where).toList(),
                  txViews: ds.txViews,
                  categories: ds.categories,
                  accountsByKey: ds.accountsByKey,
                  tagsByKey: ds.tagsByKey,
                  projectsByKey: ds.projectsByKey,
                ));
                final s = agg.summary();
                final total = flow == ReportFlow.reward
                    ? agg.rewardTotal(rewards)
                    : s.amountFor(flow);
                final count = flow == ReportFlow.reward
                    ? agg.transactions().length
                    : switch (flow) {
                        ReportFlow.income => s.incomeCount,
                        ReportFlow.transfer => s.transferCount,
                        _ => s.expenseCount,
                      };
                final txs = agg.transactions();
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Text(l10n.reportTxCount(count),
                              style: BeeTextTokens.label(context)),
                          const Spacer(),
                          Text('${reportFlowLabel(l10n, flow)} ',
                              style: BeeTextTokens.label(context)),
                          AmountText(
                            value: total,
                            signed: false,
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: reportFlowColor(context, ref, flow)),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: BeeTokens.divider(context)),
                    Expanded(
                      child: TransactionList(
                        transactions: txs,
                        hideAmounts: ref.watch(hideAmountsProvider),
                        emptyWidget: AppEmpty(text: l10n.commonEmpty),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 類別下鑽(有篩選時):一級分類 + 子分類在報表篩選下的交易。
void openReportCategoryDrilldown(
  BuildContext context,
  ReportView view, {
  required String type,
  required int categoryId,
  required String name,
  List<int> childIds = const [],
}) {
  final ids = {categoryId, ...childIds};
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ReportTransactionsPage(
      title: name,
      subtitle: view.periodLabel,
      query: view.query,
      flow: type,
      where: (e) => e.type == type && ids.contains(e.categoryId),
    ),
  ));
}
