// 股票持股計算 — 跑 App/Cloud 共用測試向量(test/fixtures/stock_holdings_vectors.json,
// 內容必須跟 BeeCount-Cloud/tests/fixtures/stock_holdings_vectors.json 相同)。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/investment/holdings_calculator.dart';

void main() {
  final data = jsonDecode(File('test/fixtures/stock_holdings_vectors.json').readAsStringSync())
      as Map<String, dynamic>;
  final cases = (data['cases'] as List).cast<Map<String, dynamic>>();

  for (final c in cases) {
    test('shared vector: ${c['name']}', () {
      final trades = (c['trades'] as List)
          .cast<Map<String, dynamic>>()
          .map(HoldingTrade.fromWire);
      final got = HoldingsCalculator.compute(trades, includeClosed: true);
      final expected = (c['expected'] as List).cast<Map<String, dynamic>>();
      expect(got.length, expected.length);
      for (var i = 0; i < got.length; i++) {
        final g = got[i];
        final e = expected[i];
        expect(g.accountKey, e['accountId']);
        expect(g.market, e['market']);
        expect(g.symbol, e['symbol']);
        expect(g.shares, closeTo((e['shares'] as num).toDouble(), 1e-6));
        expect(g.totalCost, closeTo((e['totalCost'] as num).toDouble(), 1e-6));
        expect(g.avgCost, closeTo((e['avgCost'] as num).toDouble(), 1e-6));
        expect(g.realizedPnl, closeTo((e['realizedPnl'] as num).toDouble(), 1e-6));
        expect(g.dividends, closeTo((e['dividends'] as num).toDouble(), 1e-6));
      }
    });
  }

  test('closed positions are excluded by default', () {
    const trades = [
      HoldingTrade(syncId: 'a', accountKey: '1', market: 'US', symbol: 'X', tradeType: 'buy',
          shares: 1, price: 10, fee: 0, tax: 0, amount: 10, tradeDateKey: '2026-01-01'),
      HoldingTrade(syncId: 'b', accountKey: '1', market: 'US', symbol: 'X', tradeType: 'sell',
          shares: 1, price: 12, fee: 0, tax: 0, amount: 12, tradeDateKey: '2026-01-02'),
    ];
    expect(HoldingsCalculator.compute(trades), isEmpty);
    expect(HoldingsCalculator.compute(trades, includeClosed: true).single.realizedPnl, closeTo(2, 1e-9));
  });

  test('vector file matches the Cloud copy when both repos are checked out side by side', () {
    final cloud = File('../../BeeCount-Cloud/tests/fixtures/stock_holdings_vectors.json');
    if (!cloud.existsSync()) return; // CI 只 checkout 這個 repo 時跳過
    expect(File('test/fixtures/stock_holdings_vectors.json').readAsStringSync(),
        cloud.readAsStringSync());
  });
}
