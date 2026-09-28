import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'holding_detail_page.dart';
import 'holding_tile.dart';
import 'investment_ui.dart';
import 'pending_dividends_page.dart';

/// 帳戶頁淨資產卡下方的「投資市值(預估)」卡(使用者確認的需求:股票不算淨
/// 資產,另外顯示)。折算成使用者主幣別,口徑同淨資產卡(缺匯率剔除並標示)。
/// 沒有任何未平倉部位時不顯示。點擊進 [InvestmentsOverviewPage]。
class InvestmentMarketValueCard extends ConsumerWidget {
  /// 總覽頁自己也放一張,那邊不需要再點進總覽。
  final bool navigateOnTap;

  const InvestmentMarketValueCard({super.key, this.navigateOnTap = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(investmentSummaryProvider);
    if (summary == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final base = summary.baseCurrency;
    String money(double v, {bool signed = false}) =>
        hide ? '****' : formatStockMoney(v, base, signed: signed);
    final pnl = summary.unrealizedPnl;
    final pct = summary.unrealizedPnlPercent;
    // 只有帳戶頁那張可以折疊(折疊狀態持久化);總覽頁那張永遠展開。
    final collapsible = navigateOnTap;
    final hasPendingDividends =
        ref.watch(pendingDividendsProvider.select((s) => s.items.isNotEmpty));
    final collapsed =
        collapsible && ref.watch(sectionCollapsedProvider('investmentValue'));
    final toggleButton = collapsible
        ? SizedBox(
            width: 32,
            height: 24,
            child: IconButton(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              onPressed: () => ref
                  .read(sectionCollapsedProvider('investmentValue').notifier)
                  .toggle(),
              icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less,
                  size: 20, color: BeeTokens.iconTertiary(context)),
            ),
          )
        : null;

    return Padding(
      padding: EdgeInsets.only(top: 12.0.scaled(context, ref)),
      child: SectionCard(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: navigateOnTap
              ? () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const InvestmentsOverviewPage()))
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // 折疊時看不到「N 筆股利待確認」那一行,在圖示右上角加個點提示。
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.candlestick_chart_outlined,
                          size: 18, color: BeeTokens.iconSecondary(context)),
                      if (collapsed && hasPendingDividends)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: ref.watch(primaryColorProvider),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.stockMarketValueCardTitle,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: BeeTokens.textPrimary(context)),
                  ),
                  const Spacer(),
                  if (collapsed) ...[
                    Text(
                      money(summary.marketValue),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: BeeTokens.textPrimary(context)),
                    ),
                    if (pct != null) ...[
                      const SizedBox(width: 6),
                      Text(formatPercent(pct),
                          style: TextStyle(
                              fontSize: 12,
                              color: pnlColor(context, ref, pnl))),
                    ],
                  ],
                  if (toggleButton != null) toggleButton,
                  if (navigateOnTap && !collapsed)
                    Icon(Icons.chevron_right,
                        size: 18, color: BeeTokens.iconTertiary(context)),
                ],
              ),
              if (!collapsed) ...[
                const SizedBox(height: 8),
                Text(
                  money(summary.marketValue),
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: BeeTokens.textPrimary(context)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.stockUnrealizedPnl} ${money(pnl, signed: true)}${pct == null ? '' : ' (${formatPercent(pct)})'}',
                  style: TextStyle(
                      fontSize: 13, color: pnlColor(context, ref, pnl)),
                ),
                if (summary.pnlAfterSellCosts)
                  Text(
                    '${l10n.stockPnlAfterSellCostsNote} · ${l10n.stockNetValue} ${money(summary.netValue)}',
                    style: TextStyle(
                        fontSize: 11, color: BeeTokens.textTertiary(context)),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${l10n.stockCost} ${money(summary.cost)}',
                  style: TextStyle(
                      fontSize: 12, color: BeeTokens.textSecondary(context)),
                ),
                if (summary.unpricedCount > 0)
                  Text(l10n.stockUnpricedCount(summary.unpricedCount),
                      style: TextStyle(
                          fontSize: 12, color: BeeTokens.warning(context))),
                if (summary.missingCurrencies.isNotEmpty)
                  Text(
                      l10n.stockMissingRates(
                          summary.missingCurrencies.join(', ')),
                      style: TextStyle(
                          fontSize: 12, color: BeeTokens.warning(context))),
                // 待確認股利(Phase 2)入口;沒有待確認時不顯示。
                const PendingDividendsBanner(inCard: true),
                const SizedBox(height: 6),
                Text(
                  [
                    l10n.stockMarketValueCardHint,
                    if (summary.oldestQuoteTime != null)
                      l10n.stockQuoteAsOf(
                          formatQuoteTime(summary.oldestQuoteTime!)),
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 11, color: BeeTokens.textTertiary(context)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 所有投資理財帳戶的持股總覽(依帳戶分組)。
class InvestmentsOverviewPage extends ConsumerWidget {
  const InvestmentsOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final holdings = ref.watch(allHoldingsProvider) ?? const <HoldingView>[];
    final accounts =
        ref.watch(allAccountsStreamProvider).valueOrNull ?? const <Account>[];
    final byId = {for (final a in accounts) a.id: a};
    final grouped = <int, List<HoldingView>>{};
    for (final h in holdings.where((h) => h.holding.isOpen)) {
      final id = h.accountId;
      if (id == null || !byId.containsKey(id)) continue;
      grouped.putIfAbsent(id, () => []).add(h);
    }
    for (final list in grouped.values) {
      list.sort((a, b) => (b.marketValue ?? b.holding.totalCost)
          .compareTo(a.marketValue ?? a.holding.totalCost));
    }

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
              title: l10n.stockOverviewTitle, showBack: true, compact: true),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(quoteRefreshProvider.notifier).refresh(force: true),
              child: ListView(
                padding: EdgeInsets.symmetric(
                    horizontal: 12.0.scaled(context, ref),
                    vertical: 8.0.scaled(context, ref)),
                children: [
                  const InvestmentMarketValueCard(navigateOnTap: false),
                  for (final entry in grouped.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                      child: Text(
                        byId[entry.key]!.name,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: BeeTokens.textPrimary(context)),
                      ),
                    ),
                    SectionCard(
                      margin: EdgeInsets.zero,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < entry.value.length; i++) ...[
                            if (i > 0)
                              Divider(
                                  height: 1, color: BeeTokens.divider(context)),
                            HoldingTile(
                              view: entry.value[i],
                              onTap: () =>
                                  Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => HoldingDetailPage(
                                  account: byId[entry.key]!,
                                  market: entry.value[i].holding.market,
                                  symbol: entry.value[i].holding.symbol,
                                ),
                              )),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 24.0.scaled(context, ref)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
