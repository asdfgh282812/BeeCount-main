// 庫存預估變現淨值(2026-09-28 台股費用對帳):HoldingView / InvestmentSummary
// 預設用「市值 − 預估賣出手續費 − 預估交易稅」算未實現損益,帳戶設定關掉
// pnlAfterSellCosts 時退回毛市值。Cloud `/workspace/holdings` 同一套規則。
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/models/investment_settings.dart';
import 'package:beecount/providers/securities_providers.dart';
import 'package:beecount/services/investment/holdings_calculator.dart';

HoldingView view0050(InvestmentSettings settings) {
  final holding = HoldingsCalculator.compute([
    const HoldingTrade(
      syncId: 't1',
      accountKey: '2',
      market: 'TW',
      symbol: '0050',
      tradeType: 'buy',
      shares: 50,
      price: 97.45,
      fee: 6,
      tax: 0,
      amount: 4878,
      tradeDateKey: '2026-09-01',
      currency: 'TWD',
    ),
  ]).single;
  return HoldingView(
    holding: holding,
    accountId: 2,
    quote: SecurityQuote(
        market: 'TW',
        symbol: '0050',
        currency: 'TWD',
        price: 112.40,
        fetchedAt: DateTime(2026, 9, 28)),
    settings: settings,
  );
}

void main() {
  test('預設:未實現損益 = 預估變現淨值 − 成本', () {
    final v = view0050(const InvestmentSettings(feeDiscount: 0.6, feeMin: 1));
    expect(v.marketValue, closeTo(5620, 1e-9));
    expect(v.sellEstimate!.fee, 4);
    expect(v.sellEstimate!.tax, 5);
    expect(v.netValue, 5611);
    expect(v.unrealizedPnl, 5611 - 4878);

    final summary =
        computeInvestmentSummary(holdings: [v], rates: const {}, base: 'TWD')!;
    expect(summary.marketValue, closeTo(5620, 1e-9));
    expect(summary.netValue, 5611);
    expect(summary.unrealizedPnl, 5611 - 4878);
    expect(summary.pnlAfterSellCosts, isTrue);
  });

  test('關掉 pnlAfterSellCosts:損益回到毛市值 − 成本', () {
    final v = view0050(const InvestmentSettings(pnlAfterSellCosts: false));
    expect(v.unrealizedPnl, closeTo(5620 - 4878, 1e-9));
    final summary =
        computeInvestmentSummary(holdings: [v], rates: const {}, base: 'TWD')!;
    expect(summary.pnlAfterSellCosts, isFalse);
    expect(summary.unrealizedPnl, closeTo(5620 - 4878, 1e-9));
  });
}
