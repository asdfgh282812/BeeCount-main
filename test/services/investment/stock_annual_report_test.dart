import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/investment/holdings_calculator.dart';
import 'package:beecount/services/investment/stock_annual_report.dart';

int _seq = 0;

HoldingTrade t(String type, double shares, double amount, String date,
        {String market = 'TW',
        String symbol = '2330',
        String? name,
        double fee = 0,
        double tax = 0,
        String? currency,
        String account = '1'}) =>
    HoldingTrade(
        syncId: 'id${_seq++}',
        accountKey: account,
        market: market,
        symbol: symbol,
        tradeType: type,
        shares: shares,
        price: null,
        fee: fee,
        tax: tax,
        amount: amount,
        tradeDateKey: date,
        securityName: name,
        currency: currency);

StockCurrencyAnnual only(StockAnnualBundle b) {
  expect(b.currencies.length, 1);
  return b.currencies.first;
}

void main() {
  setUp(() => _seq = 0);

  test('沒有該年度交易時回傳空', () {
    final b = StockAnnualReport.build([t('buy', 100, 1000, '2025-03-01')],
        year: 2026);
    expect(b.isEmpty, isTrue);
  });

  test('跨年成本延續:去年買、今年賣,成本用全部歷史算', () {
    final b = StockAnnualReport.build([
      t('buy', 100, 10000, '2025-06-01'), // 去年買,均價 100
      t('sell', 50, 6000, '2026-02-10'), // 成本 5000 → +1000
    ], year: 2026);
    final c = only(b);
    expect(c.currency, 'TWD');
    expect(c.buyCount, 0);
    expect(c.sellCount, 1);
    expect(c.realizedPnl, closeTo(1000, 1e-9));
    expect(c.sellAmount, 6000);
    // 去年那年不應有已實現損益,但有買進。
    final prev = StockAnnualReport.build([
      t('buy', 100, 10000, '2025-06-01'),
      t('sell', 50, 6000, '2026-02-10'),
    ], year: 2025);
    final p = only(prev);
    expect(p.realizedPnl, 0);
    expect(p.buyAmount, 10000);
    expect(prev.firstBuyThisYear, isTrue);
    expect(b.firstBuyThisYear, isFalse);
  });

  test('勝率:pnl>0 勝、<0 敗、==0 不計;最賺最賠含報酬率', () {
    final b = StockAnnualReport.build([
      t('buy', 100, 10000, '2026-01-02', symbol: 'A', name: '甲'),
      t('sell', 10, 1500, '2026-01-10', symbol: 'A', name: '甲'), // 成本 1000 → +500
      t('sell', 10, 1000, '2026-01-11', symbol: 'A', name: '甲'), // 成本 1000 → 0
      t('sell', 10, 600, '2026-01-12', symbol: 'A', name: '甲'), // 成本 1000 → -400
      t('sell', 10, 1200, '2026-01-13', symbol: 'A', name: '甲'), // +200
    ], year: 2026);
    final c = only(b);
    expect(c.winCount, 2);
    expect(c.lossCount, 1);
    expect(c.decidedCount, 3);
    expect(c.winRate, closeTo(2 / 3, 1e-9));
    expect(c.realizedPnl, closeTo(300, 1e-9));
    expect(c.bestSell!.pnl, closeTo(500, 1e-9));
    expect(c.bestSell!.returnRate, closeTo(0.5, 1e-9));
    expect(c.bestSell!.displayName, '甲');
    expect(c.bestSell!.date, '2026-01-10');
    expect(c.worstSell!.pnl, closeTo(-400, 1e-9));
    expect(c.worstSell!.returnRate, closeTo(-0.4, 1e-9));
  });

  test('沒有勝負資料時勝率為 0 且 decidedCount 為 0', () {
    final c = only(StockAnnualReport.build(
        [t('buy', 10, 100, '2026-01-01')],
        year: 2026));
    expect(c.decidedCount, 0);
    expect(c.winRate, 0);
    expect(c.bestSell, isNull);
    expect(c.worstSell, isNull);
  });

  test('單月分桶:已實現損益與股利各自落在正確月份', () {
    final b = StockAnnualReport.build([
      t('buy', 100, 10000, '2026-01-02'),
      t('sell', 10, 1500, '2026-03-05'), // +500 → 3 月
      t('sell', 10, 800, '2026-03-20'), // -200 → 3 月
      t('sell', 10, 1100, '2026-12-31'), // +100 → 12 月
      t('cash_dividend', 100, 300, '2026-07-15'),
      t('reinvest', 5, 50, '2026-07-16', symbol: 'B'),
    ], year: 2026);
    final c = only(b);
    expect(c.monthlyRealizedPnl.length, 12);
    expect(c.monthlyRealizedPnl[2], closeTo(300, 1e-9));
    expect(c.monthlyRealizedPnl[11], closeTo(100, 1e-9));
    expect(c.monthlyRealizedPnl[0], 0);
    expect(c.monthlyDividends.length, 12);
    expect(c.monthlyDividends[6], 350);
    expect(c.dividends, 350);
    expect(c.dividendCount, 2);
    // reinvest 不算買進
    expect(c.buyCount, 1);
    expect(c.buyAmount, 10000);
  });

  test('費用、稅、標的數、最常交易標的、領息王、市場分佈', () {
    final b = StockAnnualReport.build([
      t('buy', 100, 10020, '2026-01-02',
          symbol: '2330', name: '台積電', fee: 20),
      t('buy', 100, 5010, '2026-01-03', symbol: '0050', name: '元大台灣50', fee: 10),
      t('buy', 100, 5010, '2026-01-04', symbol: '0050', name: '元大台灣50', fee: 10),
      t('sell', 100, 5900, '2026-02-01',
          symbol: '0050', name: '元大台灣50', fee: 10, tax: 90),
      t('cash_dividend', 100, 900, '2026-08-01', symbol: '2330', name: '台積電'),
      t('cash_dividend', 100, 200, '2026-08-02', symbol: '0050'),
    ], year: 2026);
    final c = only(b);
    expect(c.fees, 50);
    expect(c.taxes, 90);
    expect(c.symbolCount, 2);
    expect(c.topSymbolByTrades!.symbol, '0050');
    expect(c.topSymbolByTrades!.value, 3);
    expect(c.topSymbolByTrades!.displayName, '元大台灣50');
    expect(c.topDividendSymbol!.symbol, '2330');
    expect(c.topDividendSymbol!.value, 900);
    expect(c.marketBreakdown, {'TW': 6});
    expect(c.buyAmount, 20040);
    expect(c.sellAmount, 5900);
  });

  test('多幣別分開並依活躍度(買+賣金額)由大到小排序', () {
    final b = StockAnnualReport.build([
      t('buy', 10, 1000, '2026-01-01', market: 'US', symbol: 'AAPL'),
      t('buy', 100, 50000, '2026-01-01'),
      t('buy', 10, 20, '2026-01-01', market: 'HK', symbol: '0700'),
    ], year: 2026);
    expect(b.currencies.map((c) => c.currency).toList(),
        ['TWD', 'USD', 'HKD']);
    expect(b.primary!.currency, 'TWD');
    expect(b.currencies[1].marketBreakdown, {'US': 1});
  });

  test('明細無幣別且市場未知時,退回帳戶幣別對應', () {
    final b = StockAnnualReport.build([
      t('buy', 1, 100, '2026-01-01', market: 'XX', symbol: 'Z', account: '9'),
    ], year: 2026, accountCurrency: {'9': 'eur'});
    expect(only(b).currency, 'EUR');
  });

  group('styleTag', () {
    StockStyleTag tag(List<HoldingTrade> trades) =>
        only(StockAnnualReport.build(trades, year: 2026)).styleTag;

    test('activeTrader:buy+sell >= 40', () {
      final trades = <HoldingTrade>[
        t('buy', 1000, 100000, '2026-01-01'),
        for (var i = 0; i < 39; i++) t('buy', 1, 10, '2026-01-02'),
      ];
      expect(tag(trades), StockStyleTag.activeTrader);
    });

    test('activeTrader 優先於 dividendHunter', () {
      final trades = <HoldingTrade>[
        for (var i = 0; i < 40; i++) t('buy', 1, 10, '2026-01-02'),
        t('cash_dividend', 1, 99999, '2026-02-01'),
        t('cash_dividend', 1, 99999, '2026-03-01'),
      ];
      expect(tag(trades), StockStyleTag.activeTrader);
    });

    test('dividendHunter:股利 >= |已實現損益| 且 >= 2 筆', () {
      final trades = [
        t('buy', 100, 10000, '2026-01-01'),
        t('sell', 10, 1100, '2026-02-01'), // +100
        t('cash_dividend', 100, 300, '2026-07-01'),
        t('cash_dividend', 100, 300, '2026-10-01'),
      ];
      expect(tag(trades), StockStyleTag.dividendHunter);
    });

    test('只有 1 筆股利不算 dividendHunter', () {
      final trades = [
        t('buy', 100, 10000, '2026-01-01'),
        t('cash_dividend', 100, 300, '2026-07-01'),
      ];
      expect(tag(trades), StockStyleTag.longTermHolder);
    });

    test('longTermHolder:只買不賣', () {
      expect(tag([t('buy', 100, 10000, '2026-01-01')]),
          StockStyleTag.longTermHolder);
    });

    test('longTermHolder:買進 >= 3 倍賣出', () {
      final trades = [
        t('buy', 100, 10000, '2026-01-01'),
        t('buy', 100, 10000, '2026-02-01'),
        t('buy', 100, 10000, '2026-03-01'),
        t('sell', 10, 1000, '2026-04-01'),
      ];
      expect(tag(trades), StockStyleTag.longTermHolder);
    });

    test('swingTrader:有賣出且買進不到 3 倍賣出(買賣 >= 5 筆)', () {
      final trades = [
        t('buy', 100, 10000, '2026-01-01'),
        t('buy', 100, 10000, '2026-01-02'),
        t('buy', 100, 10000, '2026-01-03'),
        t('sell', 10, 1000, '2026-02-01'),
        t('sell', 10, 1000, '2026-02-02'),
      ];
      expect(tag(trades), StockStyleTag.swingTrader);
    });

    test('beginner:買賣不到 5 筆且有賣出', () {
      final trades = [
        t('buy', 100, 10000, '2026-01-01'),
        t('sell', 10, 1000, '2026-02-01'),
      ];
      expect(tag(trades), StockStyleTag.beginner);
    });

    test('beginner:沒有買賣也不夠格領息獵人(只有 1 筆股利)', () {
      expect(tag([t('cash_dividend', 10, 50, '2026-05-01')]),
          StockStyleTag.beginner);
    });
  });

  group('成就用 bundle 判斷', () {
    test('勝率 >= 60% 且賣出 >= 5', () {
      final b = StockAnnualReport.build([
        t('buy', 1000, 100000, '2026-01-01'),
        for (var i = 0; i < 4; i++) t('sell', 10, 1100, '2026-02-0${i + 1}'),
        t('sell', 10, 900, '2026-02-09'),
      ], year: 2026);
      expect(b.hasHighWinRate, isTrue); // 4/5 = 80%
      expect(b.hasRealizedProfit, isTrue);
    });

    test('賣出不足 5 筆不算', () {
      final b = StockAnnualReport.build([
        t('buy', 100, 10000, '2026-01-01'),
        t('sell', 10, 2000, '2026-02-01'),
      ], year: 2026);
      expect(b.hasHighWinRate, isFalse);
    });

    test('領息達人:股利 >= 3 筆', () {
      final b = StockAnnualReport.build([
        t('cash_dividend', 1, 10, '2026-01-01'),
        t('cash_dividend', 1, 10, '2026-04-01'),
        t('reinvest', 1, 10, '2026-07-01'),
      ], year: 2026);
      expect(b.isDividendCollector, isTrue);
    });

    test('opening 之後的 buy 不算首次買股', () {
      final trades = [
        t('opening', 100, 10000, '2025-12-31'),
        t('buy', 10, 1000, '2026-01-02'),
      ];
      expect(StockAnnualReport.isFirstBuyYear(trades, 2026), isFalse);
    });
  });
}
