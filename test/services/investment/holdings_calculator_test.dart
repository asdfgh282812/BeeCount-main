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
      final events = <RealizedPnlEvent>[];
      final got = HoldingsCalculator.compute(trades,
          includeClosed: true, realized: events);
      final expectedEvents = (c['realizedEvents'] as List?)
          ?.cast<Map<String, dynamic>>();
      if (expectedEvents != null) {
        expect(events.length, expectedEvents.length);
        for (var i = 0; i < events.length; i++) {
          final g = events[i];
          final e = expectedEvents[i];
          expect(g.tradeSyncId, e['tradeSyncId']);
          expect(g.accountKey, e['accountId']);
          expect(g.market, e['market']);
          expect(g.symbol, e['symbol']);
          expect(g.date, e['date']);
          expect(g.shares, closeTo((e['shares'] as num).toDouble(), 1e-6));
          expect(g.proceeds, closeTo((e['proceeds'] as num).toDouble(), 1e-6));
          expect(g.costBasis, closeTo((e['costBasis'] as num).toDouble(), 1e-6));
          expect(g.pnl, closeTo((e['pnl'] as num).toDouble(), 1e-6));
        }
      }
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

  test('realizedEvents: one per sell, oversell clamps shares, pnl sums to realizedPnl', () {
    const trades = [
      HoldingTrade(syncId: 'a', accountKey: '1', market: 'US', symbol: 'X', tradeType: 'buy',
          shares: 10, price: 10, fee: 0, tax: 0, amount: 100, tradeDateKey: '2026-01-01',
          securityName: 'Ex', currency: 'usd'),
      HoldingTrade(syncId: 'b', accountKey: '1', market: 'US', symbol: 'X', tradeType: 'sell',
          shares: 4, price: 12, fee: 0, tax: 0, amount: 48, tradeDateKey: '2026-02-01'),
      HoldingTrade(syncId: 'c', accountKey: '1', market: 'US', symbol: 'X', tradeType: 'sell',
          shares: 9, price: 8, fee: 0, tax: 0, amount: 72, tradeDateKey: '2026-03-01'),
    ];
    final events = HoldingsCalculator.realizedEvents(trades);
    expect(events.map((e) => e.tradeSyncId), ['b', 'c']);
    expect(events[0].shares, 4);
    expect(events[0].costBasis, closeTo(40, 1e-9));
    expect(events[0].pnl, closeTo(8, 1e-9));
    expect(events[1].shares, closeTo(6, 1e-9)); // 賣超只算持有的 6 股
    expect(events[1].costBasis, closeTo(60, 1e-9));
    expect(events[1].currency, 'USD');
    expect(events[1].securityName, 'Ex');
    final h = HoldingsCalculator.compute(trades, includeClosed: true).single;
    expect(events.fold<double>(0, (a, e) => a + e.pnl), closeTo(h.realizedPnl, 1e-9));
  });

  test('split ratio <= 0 is ignored', () {
    const trades = [
      HoldingTrade(syncId: 'a', accountKey: '1', market: 'US', symbol: 'X', tradeType: 'buy',
          shares: 10, price: 10, fee: 0, tax: 0, amount: 100, tradeDateKey: '2026-01-01'),
      HoldingTrade(syncId: 'b', accountKey: '1', market: 'US', symbol: 'X', tradeType: 'split',
          shares: 0, price: null, fee: 0, tax: 0, amount: 0, tradeDateKey: '2026-01-02'),
    ];
    expect(HoldingsCalculator.compute(trades).single.shares, 10);
  });

  test('vector file matches the Cloud copy when both repos are checked out side by side', () {
    final cloud = File('../../BeeCount-Cloud/tests/fixtures/stock_holdings_vectors.json');
    if (!cloud.existsSync()) return; // CI 只 checkout 這個 repo 時跳過
    expect(File('test/fixtures/stock_holdings_vectors.json').readAsStringSync(),
        cloud.readAsStringSync());
  });
}
