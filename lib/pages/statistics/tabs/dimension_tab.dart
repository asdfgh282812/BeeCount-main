import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers.dart';
import '../../../services/report/report_aggregator.dart';
import '../../../styles/tokens.dart';
import '../../../widgets/biz/account_avatar.dart';
import '../../../widgets/biz/biz.dart';
import '../../../widgets/category_icon.dart' show ThemedIconGlyph;
import '../../../widgets/charts/category_pie_chart.dart'
    show kCategoryChartColors;
import '../../../widgets/statistics/report_colors.dart';
import '../../../widgets/statistics/share_bar_row.dart';
import '../../../widgets/ui/capsule_switcher.dart';
import '../report_transactions_page.dart';
import '../report_view.dart';

/// 維度列前面的圖標,跟各實體自己的畫面一致:
/// - 帳戶/帳戶分組:資產頁的帳戶頭像(自訂 logo,沒有就用類型圖標)
/// - 專案:專案自己的圖標(emoji 或圖示)
/// - 名稱/商家/標籤/對象:本來就只是文字,不加圖標(回傳 null)
/// 「(無)」「未分組」與已刪除的實體用中性的預設圖標。
({Widget widget, bool wrap})? reportDimensionLeading(
  BuildContext context,
  WidgetRef ref,
  ReportView view,
  ReportDimension d,
  String? key,
  Color color,
) {
  switch (d) {
    case ReportDimension.account:
    case ReportDimension.accountGroup:
      final a = key == null ? null : view.ds.accountsByKey[key];
      if (a == null) {
        return (
          widget: Icon(
              d == ReportDimension.accountGroup
                  ? Icons.folder_outlined
                  : Icons.account_balance_wallet_outlined,
              size: 20,
              color: color),
          wrap: true,
        );
      }
      return (
        widget: AccountAvatar(
            account: a,
            size: 40,
            primaryColor: ref.watch(primaryColorProvider)),
        wrap: false,
      );
    case ReportDimension.project:
      final p = key == null ? null : view.ds.projectsByKey[key];
      return (
        widget: p == null
            ? Icon(Icons.flag_outlined, size: 20, color: color)
            : ThemedIconGlyph(icon: p.icon, color: color, size: 20),
        wrap: true,
      );
    case ReportDimension.name:
    case ReportDimension.merchant:
    case ReportDimension.tag:
    case ReportDimension.counterparty:
      return null;
  }
}

String reportDimensionRowLabel(
    AppLocalizations l10n, ReportDimension d, DimensionRow r) {
  if (r.key == null) {
    return d == ReportDimension.accountGroup
        ? l10n.reportUngrouped
        : l10n.reportNone;
  }
  return r.label ?? l10n.reportDeletedEntity;
}

bool _isAccountDim(ReportDimension d) =>
    d == ReportDimension.account || d == ReportDimension.accountGroup;

/// 依 [flow] 排序、過濾掉金額 ≤ 0 的列,並畫成佔比條清單。[limit] 用在總覽
/// 的「商家前 5」。[rewards] 只在 flow = 回饋金時需要。
class DimensionRankList extends ConsumerWidget {
  final ReportView view;
  final ReportDimension dimension;
  final String flow; // ReportFlow.*
  final int? limit;
  final Map<int, double> rewards;

  const DimensionRankList({
    super.key,
    required this.view,
    required this.dimension,
    required this.flow,
    this.limit,
    this.rewards = const {},
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    var rows = view.agg
        .byDimension(dimension, rewards: rewards)
        .where((r) => r.amountFor(flow) > 0)
        .toList()
      ..sort((a, b) => b.amountFor(flow).compareTo(a.amountFor(flow)));
    // 佔比分母:收支/轉帳用總額;帳戶的轉帳是轉入+轉出(同一筆算兩次),改用
    // 各列合計;回饋金用篩選後的回饋合計。
    final double total;
    if (flow == ReportFlow.reward) {
      total = view.agg.rewardTotal(rewards);
    } else if (flow == ReportFlow.transfer && _isAccountDim(dimension)) {
      total = rows.fold(0.0, (a, r) => a + r.transfer);
    } else {
      total = view.agg.summary().amountFor(flow);
    }
    if (limit != null) {
      rows = rows.where((r) => r.key != null).take(limit!).toList();
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(l10n.commonEmpty,
              style: TextStyle(color: BeeTokens.textTertiary(context))),
        ),
      );
    }
    final amountColor = reportFlowColor(context, ref, flow);
    Widget rowFor(int i, DimensionRow r) {
      final color = kCategoryChartColors[i % kCategoryChartColors.length];
      final leading =
          reportDimensionLeading(context, ref, view, dimension, r.key, color);
      final label = reportDimensionRowLabel(l10n, dimension, r);
      return ShareBarRow(
        leading: leading?.widget,
        wrapLeading: leading?.wrap ?? true,
        title: label,
        subtitle: _subtitle(l10n, r, hide),
        amount: r.amountFor(flow),
        amountColor: amountColor,
        percent: total <= 0 ? 0 : r.amountFor(flow) / total,
        color: color,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ReportTransactionsPage(
            title: label,
            subtitle: '${view.periodLabel} · ${reportFlowLabel(l10n, flow)}',
            query: view.query,
            flow: flow,
            rewards: rewards,
            where: view.agg.dimensionPredicate(dimension, r.key,
                flow: flow, rewards: rewards),
          ),
        )),
      );
    }

    return Column(
      children: [
        for (final (i, r) in rows.indexed) rowFor(i, r),
      ],
    );
  }

  String _subtitle(AppLocalizations l10n, DimensionRow r, bool hide) {
    final parts = [l10n.reportTxCount(r.countFor(flow))];
    if (!hide && flow == ReportFlow.transfer && _isAccountDim(dimension)) {
      if (r.transferIn > 0) {
        parts.add(
            '${l10n.transferToPrefix} ${formatMoneyCompact(r.transferIn, maxDecimals: 0)}');
      }
      if (r.transferOut > 0) {
        parts.add(
            '${l10n.transferFromPrefix} ${formatMoneyCompact(r.transferOut, maxDecimals: 0)}');
      }
    }
    return parts.join(' · ');
  }
}

/// 單一維度的分頁:上方支出/收入/轉帳/回饋金切換 + 排行清單。
class ReportDimensionTab extends ConsumerStatefulWidget {
  final ReportView view;
  final List<ReportDimension> dimensions;

  /// 多個維度時每段的標題(例:標籤和對象)。
  final List<String>? sectionTitles;
  final String? footnote;

  const ReportDimensionTab({
    super.key,
    required this.view,
    required this.dimensions,
    this.sectionTitles,
    this.footnote,
  });

  @override
  ConsumerState<ReportDimensionTab> createState() => _ReportDimensionTabState();
}

class _ReportDimensionTabState extends ConsumerState<ReportDimensionTab>
    with AutomaticKeepAliveClientMixin {
  String _flow = ReportFlow.expense;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final view = widget.view;
    final isReward = _flow == ReportFlow.reward;
    final rewardsAsync =
        isReward ? ref.watch(reportRewardsProvider(view.query)) : null;
    final rewards = rewardsAsync?.valueOrNull ?? const <int, double>{};
    final total = isReward
        ? view.agg.rewardTotal(rewards)
        : view.agg.summary().amountFor(_flow);
    final notes = [
      if (isReward) l10n.reportRewardNote,
      if (_flow == ReportFlow.transfer && widget.dimensions.any(_isAccountDim))
        l10n.reportTransferAccountNote,
      if (widget.footnote != null) widget.footnote!,
    ];
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, reportBottomPadding(context)),
      children: [
        CapsuleSwitcher<String>(
          selectedValue: _flow,
          height: 34,
          options: [
            for (final f in ReportFlow.all)
              CapsuleOption(value: f, label: reportFlowLabel(l10n, f)),
          ],
          onChanged: (f) => setState(() => _flow = f),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(reportFlowLabel(l10n, _flow),
                style: BeeTextTokens.label(context)),
            const SizedBox(width: 6),
            AmountText(
                value: total,
                signed: false,
                style: BeeTextTokens.title(context)
                    .copyWith(color: reportFlowColor(context, ref, _flow))),
          ],
        ),
        const SizedBox(height: 8),
        if (rewardsAsync != null && rewardsAsync.isLoading && rewards.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final (i, d) in widget.dimensions.indexed) ...[
            if (widget.sectionTitles != null) ...[
              const SizedBox(height: 12),
              Text(widget.sectionTitles![i],
                  style: BeeTextTokens.title(context)),
              const SizedBox(height: 4),
            ],
            DimensionRankList(
                view: view, dimension: d, flow: _flow, rewards: rewards),
          ],
        for (final n in notes) ...[
          const SizedBox(height: 12),
          Text(n,
              style: TextStyle(
                  fontSize: 11, color: BeeTokens.textTertiary(context))),
        ],
      ],
    );
  }
}
