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
import 'investment_settings_page.dart';
import 'investment_ui.dart';
import 'pending_dividends_page.dart';
import 'recurring_stock_rule_editor_page.dart';
import 'stock_trade_editor_page.dart';

/// 投資理財帳戶詳情頁的「持股」分頁(docs/changes/2026-09-28-stock-holdings.md)。
///
/// 上方是市值/成本/損益摘要(以證券幣別分開列,一個帳戶可能同時有台股跟
/// 美股),下面是持股清單,最底是已出清的部位(只剩已實現損益)。
class InvestmentHoldingsView extends ConsumerStatefulWidget {
  final Account account;

  const InvestmentHoldingsView({super.key, required this.account});

  @override
  ConsumerState<InvestmentHoldingsView> createState() =>
      _InvestmentHoldingsViewState();
}

class _InvestmentHoldingsViewState
    extends ConsumerState<InvestmentHoldingsView> {
  bool _showClosed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(quoteRefreshProvider.notifier).refresh();
        ref.read(pendingDividendsProvider.notifier).refresh();
      }
    });
  }

  void _addTrade() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => StockTradeEditorPage(account: widget.account)));
  }

  void _openRecurringStock() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            RecurringStockRuleEditorPage(account: widget.account)));
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => InvestmentSettingsPage(account: widget.account)));
  }

  Future<void> _refresh() async {
    final l10n = AppLocalizations.of(context);
    await Future.wait([
      ref.read(quoteRefreshProvider.notifier).refresh(force: true),
      ref.read(pendingDividendsProvider.notifier).refresh(force: true),
    ]);
    final err = ref.read(quoteRefreshProvider).lastError;
    if (err != null && mounted) showToast(context, l10n.stockRefreshFailed);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final views = ref.watch(accountHoldingsProvider(widget.account.id));
    final refreshState = ref.watch(quoteRefreshProvider);
    final cloudAvailable =
        ref.watch(securitiesCloudAvailableProvider).valueOrNull ?? false;
    if (views == null)
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));

    final open = views.where((v) => v.holding.isOpen).toList()
      ..sort((a, b) => (b.marketValue ?? b.holding.totalCost)
          .compareTo(a.marketValue ?? a.holding.totalCost));
    final closed = views.where((v) => !v.holding.isOpen).toList();

    final mvByCcy = <String, double>{};
    // 算未實現損益用的價值(扣預估賣出費用時是淨值),同各檔 HoldingView.valuation。
    final valuationByCcy = <String, double>{};
    final netByCcy = <String, double>{};
    var afterCosts = false;
    final costByCcy = <String, double>{};
    var unpriced = 0;
    DateTime? oldestQuote;
    for (final v in open) {
      final mv = v.marketValue;
      if (mv == null) {
        unpriced++;
        continue;
      }
      mvByCcy.update(v.currency, (x) => x + mv, ifAbsent: () => mv);
      final valuation = v.valuation ?? mv;
      valuationByCcy.update(v.currency, (x) => x + valuation,
          ifAbsent: () => valuation);
      final net = v.netValue ?? mv;
      netByCcy.update(v.currency, (x) => x + net, ifAbsent: () => net);
      if (v.pnlAfterSellCosts) afterCosts = true;
      costByCcy.update(v.currency, (x) => x + v.holding.totalCost,
          ifAbsent: () => v.holding.totalCost);
      final qt = v.quote?.quoteTime ?? v.quote?.fetchedAt;
      if (qt != null && (oldestQuote == null || qt.isBefore(oldestQuote)))
        oldestQuote = qt;
    }
    String money(double v, String ccy, {bool signed = false}) =>
        hide ? '****' : formatStockMoney(v, ccy, signed: signed);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: EdgeInsets.symmetric(
            horizontal: 12.0.scaled(context, ref),
            vertical: 8.0.scaled(context, ref)),
        children: [
          PendingDividendsBanner(accountId: widget.account.id),
          if (open.isNotEmpty)
            SectionCard(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.stockMarketValue,
                      style:
                          TextStyle(color: BeeTokens.textSecondary(context))),
                  const SizedBox(height: 6),
                  for (final e in mvByCcy.entries) ...[
                    Text(
                      money(e.value, e.key),
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: BeeTokens.textPrimary(context)),
                    ),
                    Builder(builder: (context) {
                      final cost = costByCcy[e.key] ?? 0;
                      final pnl = (valuationByCcy[e.key] ?? e.value) - cost;
                      final pct = cost > 0 ? pnl / cost * 100 : null;
                      return Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${l10n.stockCost} ${money(cost, e.key)} · ${l10n.stockUnrealizedPnl} '
                              '${money(pnl, e.key, signed: true)}${pct == null ? '' : ' (${formatPercent(pct)})'}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: pnlColor(context, ref, pnl)),
                            ),
                            if (afterCosts)
                              Text(
                                '${l10n.stockPnlAfterSellCostsNote} · ${l10n.stockNetValue} ${money(netByCcy[e.key] ?? e.value, e.key)}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: BeeTokens.textTertiary(context)),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                  if (unpriced > 0)
                    Text(l10n.stockUnpricedCount(unpriced),
                        style: TextStyle(
                            fontSize: 12, color: BeeTokens.warning(context))),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          cloudAvailable
                              ? (oldestQuote == null
                                  ? ''
                                  : l10n.stockQuoteAsOf(
                                      formatQuoteTime(oldestQuote)))
                              : l10n.stockNoCloudHint,
                          style: TextStyle(
                              fontSize: 12,
                              color: BeeTokens.textTertiary(context)),
                        ),
                      ),
                      if (cloudAvailable)
                        refreshState.refreshing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: l10n.stockRefreshQuotes,
                                icon: Icon(Icons.refresh,
                                    size: 20,
                                    color: BeeTokens.iconSecondary(context)),
                                onPressed: _refresh,
                              ),
                    ],
                  ),
                ],
              ),
            ),
          if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
              child: Column(
                children: [
                  Icon(Icons.candlestick_chart_outlined,
                      size: 48, color: BeeTokens.iconTertiary(context)),
                  const SizedBox(height: 12),
                  Text(
                    l10n.stockNoHoldings,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: BeeTokens.textSecondary(context)),
                  ),
                ],
              ),
            ),
          SizedBox(height: 12.0.scaled(context, ref)),
          FilledButton.icon(
              onPressed: _addTrade,
              icon: const Icon(Icons.add),
              label: Text(l10n.stockAddTrade)),
          SizedBox(height: 8.0.scaled(context, ref)),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openRecurringStock,
                  icon: const Icon(Icons.repeat, size: 18),
                  label: Text(l10n.recurringStockEntryLabel,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text(l10n.stockFeeSettings,
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
          if (open.isNotEmpty) ...[
            SizedBox(height: 12.0.scaled(context, ref)),
            SectionCard(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < open.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, color: BeeTokens.divider(context)),
                    HoldingTile(
                        view: open[i], onTap: () => _openHolding(open[i])),
                  ],
                ],
              ),
            ),
          ],
          if (closed.isNotEmpty) ...[
            TextButton.icon(
              onPressed: () => setState(() => _showClosed = !_showClosed),
              icon: Icon(_showClosed ? Icons.expand_less : Icons.expand_more),
              label: Text('${l10n.stockClosedPositions} (${closed.length})'),
            ),
            if (_showClosed)
              SectionCard(
                margin: EdgeInsets.zero,
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < closed.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: BeeTokens.divider(context)),
                      HoldingTile(
                          view: closed[i],
                          onTap: () => _openHolding(closed[i])),
                    ],
                  ],
                ),
              ),
          ],
          SizedBox(height: 24.0.scaled(context, ref)),
        ],
      ),
    );
  }

  void _openHolding(HoldingView v) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HoldingDetailPage(
          account: widget.account,
          market: v.holding.market,
          symbol: v.holding.symbol),
    ));
  }
}
