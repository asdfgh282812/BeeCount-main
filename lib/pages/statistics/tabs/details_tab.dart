import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../../styles/tokens.dart';
import '../../../widgets/biz/biz.dart';
import '../../../widgets/ui/capsule_switcher.dart';
import '../report_view.dart';
import 'report_trend.dart';

/// 「明細」分頁:可收合的趨勢圖 + 期間內全部記錄(含轉帳),可切換新→舊 /
/// 舊→新;點趨勢圖上的點會把列表捲到那一天。
class ReportDetailsTab extends ConsumerStatefulWidget {
  final ReportView view;
  const ReportDetailsTab({super.key, required this.view});

  @override
  ConsumerState<ReportDetailsTab> createState() => _ReportDetailsTabState();
}

class _ReportDetailsTabState extends ConsumerState<ReportDetailsTab>
    with AutomaticKeepAliveClientMixin {
  final _listKey = GlobalKey<TransactionListState>();
  bool _ascending = false;
  bool _chartExpanded = true;
  String _type = 'expense';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final v = widget.view;
    final txs = v.agg.transactions();
    final trend = ReportTrendData.build(context, v, _type);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: CapsuleSwitcher<String>(
                  selectedValue: _type,
                  height: 32,
                  options: [
                    CapsuleOption(value: 'expense', label: l10n.homeExpense),
                    CapsuleOption(value: 'income', label: l10n.homeIncome),
                    CapsuleOption(value: 'balance', label: l10n.homeBalance),
                  ],
                  onChanged: (t) => setState(() => _type = t),
                ),
              ),
              IconButton(
                tooltip: l10n.analyticsTrendTitle,
                icon: Icon(
                  _chartExpanded ? Icons.expand_less : Icons.show_chart,
                  color: BeeTokens.iconSecondary(context),
                ),
                onPressed: () =>
                    setState(() => _chartExpanded = !_chartExpanded),
              ),
              IconButton(
                tooltip:
                    _ascending ? l10n.reportSortOldest : l10n.reportSortNewest,
                icon: Icon(
                  _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                  color: BeeTokens.iconSecondary(context),
                ),
                onPressed: () => setState(() => _ascending = !_ascending),
              ),
            ],
          ),
        ),
        if (_chartExpanded && trend.values.length >= 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: ReportTrendChart(
              data: trend,
              view: v,
              height: 180,
              onPointTap: (i) =>
                  _listKey.currentState?.jumpToDate(trend.points[i].bucket),
            ),
          ),
        Divider(height: 1, color: BeeTokens.divider(context)),
        Expanded(
          child: TransactionList(
            key: _listKey,
            transactions: txs,
            ascending: _ascending,
            hideAmounts: ref.watch(hideAmountsProvider),
            emptyWidget: AppEmpty(text: l10n.commonEmpty),
          ),
        ),
      ],
    );
  }
}
