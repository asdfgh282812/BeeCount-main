import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/investment/stock_trade_types.dart';
import '../../styles/tokens.dart';
import '../../utils/ui_scale_extensions.dart';
import '../../widgets/biz/section_card.dart';
import '../../widgets/ui/ui.dart';
import 'investment_ui.dart';
import 'stock_trade_editor_page.dart';

/// 單一持股:部位摘要 + 交易紀錄,可以加碼/賣出/手動輸入價格。
class HoldingDetailPage extends ConsumerWidget {
  final Account account;
  final String market;
  final String symbol;

  const HoldingDetailPage(
      {super.key,
      required this.account,
      required this.market,
      required this.symbol});

  Future<void> _openEditor(BuildContext context,
      {StockTrade? trade, String? type, String? name}) {
    return Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StockTradeEditorPage(
        account: account,
        trade: trade,
        initialTradeType: type,
        initialMarket: market,
        initialSymbol: symbol,
        initialName: name,
      ),
    ));
  }

  Future<void> _manualPrice(
      BuildContext context, WidgetRef ref, HoldingView view) async {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController(
        text: view.price == null
            ? ''
            : formatPrice(view.price!).replaceAll(',', ''));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BeeTokens.surfaceElevated(ctx),
        title: Text(l10n.stockSetManualPrice,
            style: TextStyle(color: BeeTokens.textPrimary(ctx))),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}'))
          ],
          decoration: InputDecoration(suffixText: view.currency),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(double.tryParse(ctrl.text)),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (value == null || value <= 0) return;
    await ref.read(quoteRefreshProvider.notifier).setManualPrice(
          market: market,
          symbol: symbol,
          price: value,
          currency: view.currency,
          name: view.name,
        );
    if (context.mounted) showToast(context, l10n.stockManualPriceSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final views =
        ref.watch(accountHoldingsProvider(account.id)) ?? const <HoldingView>[];
    final view = views
        .where((v) => v.holding.market == market && v.holding.symbol == symbol)
        .firstOrNull;
    final trades = (ref.watch(stockTradesProvider).valueOrNull ??
            const <StockTrade>[])
        .where((t) =>
            t.accountId == account.id &&
            t.market == market &&
            t.symbol == symbol)
        .toList()
      ..sort((a, b) => b.tradeDate.compareTo(a.tradeDate));
    final ccy = view?.currency ?? '';
    String money(double? v, {bool signed = false}) => v == null
        ? '—'
        : (hide ? '****' : formatStockMoney(v, ccy, signed: signed));

    Widget stat(String label, String value, {Color? color, String? note}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style:
                            TextStyle(color: BeeTokens.textSecondary(context))),
                    if (note != null)
                      Text(note,
                          style: TextStyle(
                              fontSize: 11,
                              color: BeeTokens.textTertiary(context))),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(value,
                  style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: color ?? BeeTokens.textPrimary(context))),
            ],
          ),
        );

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      body: Column(
        children: [
          PrimaryHeader(
            title: view?.name == null || view!.name!.isEmpty
                ? symbol
                : '$symbol ${view.name}',
            subtitle: '${stockMarketLabel(l10n, market)} · ${account.name}',
            showBack: true,
            compact: true,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: 12.0.scaled(context, ref),
                  vertical: 8.0.scaled(context, ref)),
              children: [
                if (view != null)
                  SectionCard(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        stat(l10n.stockMarketValue, money(view.marketValue)),
                        if (view.sellEstimate != null) ...[
                          stat(l10n.stockEstSellFee,
                              money(-view.sellEstimate!.fee)),
                          stat(l10n.stockEstSellTax,
                              money(-view.sellEstimate!.tax)),
                          stat(l10n.stockNetValue, money(view.netValue)),
                        ],
                        stat(l10n.stockShares,
                            formatShares(view.holding.shares)),
                        stat(l10n.stockAvgCost,
                            formatPrice(view.holding.avgCost)),
                        stat(l10n.stockCost, money(view.holding.totalCost)),
                        stat(
                          l10n.stockCurrentPrice,
                          view.price == null
                              ? '—'
                              : '${formatPrice(view.price!)}${view.quote?.session == null ? '' : ' · ${quoteSessionLabel(l10n, view.quote!.session)}'}',
                        ),
                        stat(
                          l10n.stockUnrealizedPnl,
                          view.unrealizedPnl == null
                              ? '—'
                              : '${money(view.unrealizedPnl, signed: true)}${view.unrealizedPnlPercent == null ? '' : ' (${formatPercent(view.unrealizedPnlPercent!)})'}',
                          color: pnlColor(context, ref, view.unrealizedPnl),
                          note: view.pnlAfterSellCosts && view.netValue != null
                              ? l10n.stockPnlAfterSellCostsNote
                              : null,
                        ),
                        stat(l10n.stockRealizedPnl,
                            money(view.holding.realizedPnl, signed: true),
                            color: pnlColor(
                                context, ref, view.holding.realizedPnl)),
                        if (view.holding.dividends > 0)
                          stat(l10n.stockDividends,
                              money(view.holding.dividends)),
                        if (view.quote?.quoteTime != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              l10n.stockQuoteAsOf(
                                  formatQuoteTime(view.quote!.quoteTime!)),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: BeeTokens.textTertiary(context)),
                            ),
                          ),
                      ],
                    ),
                  ),
                SizedBox(height: 12.0.scaled(context, ref)),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openEditor(context,
                            type: kStockTradeBuy, name: view?.name),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.stockTradeTypeBuy),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: view == null || !view.holding.isOpen
                            ? null
                            : () => _openEditor(context,
                                type: kStockTradeSell, name: view.name),
                        icon: const Icon(Icons.remove),
                        label: Text(l10n.stockTradeTypeSell),
                      ),
                    ),
                  ],
                ),
                if (view != null && view.holding.isOpen)
                  TextButton.icon(
                    onPressed: () => _manualPrice(context, ref, view),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(l10n.stockSetManualPrice),
                  ),
                SizedBox(height: 8.0.scaled(context, ref)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    l10n.stockTradeHistory,
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
                      for (var i = 0; i < trades.length; i++) ...[
                        if (i > 0)
                          Divider(height: 1, color: BeeTokens.divider(context)),
                        _TradeRow(
                          trade: trades[i],
                          hide: hide,
                          onTap: () => _openEditor(context, trade: trades[i]),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 24.0.scaled(context, ref)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TradeRow extends StatelessWidget {
  final StockTrade trade;
  final bool hide;
  final VoidCallback onTap;

  const _TradeRow(
      {required this.trade, required this.hide, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = trade.tradeType == kStockTradeStockDividend ||
            trade.price == null
        ? l10n.stockSharesCount(formatShares(trade.shares))
        : '${l10n.stockSharesCount(formatShares(trade.shares))} @ ${formatPrice(trade.price!)}';
    return ListTile(
      onTap: onTap,
      dense: true,
      title: Text(
        '${stockTradeTypeLabel(l10n, trade.tradeType)} · $detail',
        style: TextStyle(color: BeeTokens.textPrimary(context)),
      ),
      subtitle: Text(
        [
          formatTradeDate(trade.tradeDate),
          if (trade.note != null && trade.note!.isNotEmpty) trade.note!
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: BeeTokens.textSecondary(context)),
      ),
      trailing: Text(
        trade.amount == 0
            ? ''
            : (hide ? '****' : formatStockMoney(trade.amount, trade.currency)),
        style: TextStyle(
            color: BeeTokens.textPrimary(context), fontWeight: FontWeight.w500),
      ),
    );
  }
}
