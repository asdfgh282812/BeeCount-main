import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/investment/holdings_calculator.dart';
import 'package:beecount/services/investment/realized_pnl_report.dart';

HoldingTrade t(String id, String type, double shares, double amount, String date,
        {String account = '1', String market = 'TW', String symbol = '0050', double? price}) =>
    HoldingTrade(
        syncId: id,
        accountKey: account,
        market: market,
        symbol: symbol,
        tradeType: type,
        shares: shares,
        price: price,
        fee: 0,
        tax: 0,
        amount: amount,
        tradeDateKey: date);

void main() {
  final trades = [
    t('b1', 'buy', 100, 10000, '2025-01-01'),
    t('sp', 'split', 4, 0, '2025-02-01'),
    t('s1', 'sell', 100, 3000, '2025-03-01'), // cost 2500, pnl 500
    t('d1', 'cash_dividend', 300, 200, '2026-01-10'),
    t('s2', 'sell', 100, 2000, '2026-02-01'), // cost 2500, pnl -500
    t('u1', 'buy', 10, 1000, '2026-02-01', market: 'US', symbol: 'AAPL'),
    t('u2', 'sell', 5, 700, '2026-03-01', market: 'US', symbol: 'AAPL'), // cost 500, pnl 200
  ];

  test('totals are per currency and include dividends', () {
    final r = RealizedPnlReport.build(trades);
    expect(r.totals['TWD']!.pnl, closeTo(0, 1e-9));
    expect(r.totals['TWD']!.dividends, 200);
    expect(r.totals['USD']!.pnl, closeTo(200, 1e-9));
    expect(r.groups.length, 2);
  });

  test('year filter keeps cost basis from earlier years', () {
    final r = RealizedPnlReport.build(trades, filter: const RealizedFilter(year: 2026));
    expect(r.totals['TWD']!.pnl, closeTo(-500, 1e-9));
    expect(r.totals['TWD']!.dividends, 200);
    final tw = r.groups.firstWhere((g) => g.symbol == '0050');
    expect(tw.events.single.costBasis, closeTo(2500, 1e-9));
    expect(RealizedPnlReport.availableYears(trades), [2026, 2025]);
  });

  test('symbol and account filters', () {
    final bySym = RealizedPnlReport.build(trades,
        filter: const RealizedFilter(symbolKey: 'US:AAPL'));
    expect(bySym.totals.keys, ['USD']);
    expect(bySym.groups.single.events.single.pnl, closeTo(200, 1e-9));
    final byAcc = RealizedPnlReport.build(trades,
        filter: const RealizedFilter(accountKey: '2'));
    expect(byAcc.isEmpty, isTrue);
  });
}
