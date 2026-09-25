import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../../services/report/report_aggregator.dart';
import '../../../styles/tokens.dart';
import '../../../widgets/biz/biz.dart';
import '../../../widgets/statistics/report_colors.dart';
import '../../../widgets/statistics/report_tx_row.dart';
import '../../../widgets/ui/capsule_switcher.dart';
import '../report_view.dart';

/// 「排行」分頁:期間內支出/收入/轉帳依金額由大到小;回饋金依估算回饋金
/// 由大到小。
class ReportRankingTab extends ConsumerStatefulWidget {
  final ReportView view;
  const ReportRankingTab({super.key, required this.view});

  @override
  ConsumerState<ReportRankingTab> createState() => _ReportRankingTabState();
}

class _ReportRankingTabState extends ConsumerState<ReportRankingTab>
    with AutomaticKeepAliveClientMixin {
  String _flow = ReportFlow.expense;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final isReward = _flow == ReportFlow.reward;
    final rewardsAsync =
        isReward ? ref.watch(reportRewardsProvider(widget.view.query)) : null;
    final rewards = rewardsAsync?.valueOrNull ?? const <int, double>{};
    final ranked = widget.view.agg.rankedTransactions(_flow, rewards: rewards);
    final color = reportFlowColor(context, ref, _flow);
    final loading =
        rewardsAsync != null && rewardsAsync.isLoading && rewards.isEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: CapsuleSwitcher<String>(
            selectedValue: _flow,
            height: 34,
            options: [
              for (final f in ReportFlow.all)
                CapsuleOption(value: f, label: reportFlowLabel(l10n, f)),
            ],
            onChanged: (f) => setState(() => _flow = f),
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ranked.isEmpty
                  ? AppEmpty(text: l10n.commonEmpty)
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                          16, 4, 16, reportBottomPadding(context)),
                      itemCount: ranked.length + (isReward ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == ranked.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(l10n.reportRewardNote,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: BeeTokens.textTertiary(context))),
                          );
                        }
                        return ReportTxRow(
                          view: ranked[i].view,
                          amount: ranked[i].amount,
                          rank: i + 1,
                          amountColor: color,
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
