import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../styles/tokens.dart';
import 'investment_ui.dart';

/// 一檔持股的列表列:左邊代號/名稱/股數·均價,右邊市值/未實現損益。
class HoldingTile extends ConsumerWidget {
  final HoldingView view;
  final VoidCallback? onTap;

  const HoldingTile({super.key, required this.view, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hide = ref.watch(hideAmountsProvider);
    final h = view.holding;
    final ccy = view.currency;
    final mv = view.marketValue;
    final pnl = view.unrealizedPnl;
    final pnlPct = view.unrealizedPnlPercent;
    final day = view.dayChangePercent;
    final secondary =
        TextStyle(fontSize: 12, color: BeeTokens.textSecondary(context));

    String money(double? v, {bool signed = false}) => v == null
        ? '—'
        : (hide ? '****' : formatStockMoney(v, ccy, signed: signed));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: h.symbol,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: BeeTokens.textPrimary(context)),
                      ),
                      if (view.name != null && view.name!.isNotEmpty)
                        TextSpan(
                          text: '  ${view.name}',
                          style: TextStyle(
                              color: BeeTokens.textSecondary(context)),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    h.isOpen
                        ? '${l10n.stockSharesCount(formatShares(h.shares))} · ${l10n.stockAvgCost} ${formatPrice(h.avgCost)}'
                        : '${l10n.stockClosedPositions} · ${stockMarketLabel(l10n, h.market)}',
                    style: secondary,
                  ),
                  if (h.isOpen && view.price != null) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text:
                                '${l10n.stockCurrentPrice} ${formatPrice(view.price!)}',
                            style: secondary),
                        if (day != null)
                          TextSpan(
                            text: '  ${formatPercent(day)}',
                            style: TextStyle(
                                fontSize: 12,
                                color: pnlColor(context, ref, day)),
                          ),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  h.isOpen ? money(mv) : money(h.realizedPnl, signed: true),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: h.isOpen
                        ? BeeTokens.textPrimary(context)
                        : pnlColor(context, ref, h.realizedPnl),
                  ),
                ),
                if (h.isOpen) ...[
                  const SizedBox(height: 4),
                  Text(
                    pnl == null
                        ? l10n.stockSetManualPrice
                        : '${money(pnl, signed: true)}${pnlPct == null ? '' : ' (${formatPercent(pnlPct)})'}',
                    style: TextStyle(
                        fontSize: 12,
                        color: pnl == null
                            ? BeeTokens.textTertiary(context)
                            : pnlColor(context, ref, pnl)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
