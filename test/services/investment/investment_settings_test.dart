import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/models/investment_settings.dart';
import 'package:beecount/services/investment/markets.dart';
import 'package:beecount/services/investment/stock_trade_tx_mapper.dart';

void main() {
  group('InvestmentSettings', () {
    test('台股建議手續費 = floor(金額×0.1425%×折扣),低於最低手續費取最低', () {
      const s = InvestmentSettings(feeDiscount: 0.6);
      // 600,000 × 0.001425 × 0.6 = 513
      expect(s.suggestFee(600000, market: 'TW', currency: 'TWD'), 513);
      // 1,000 × 0.001425 = 1.425 → 最低 20
      expect(s.suggestFee(1000, market: 'TW', currency: 'TWD'), 20);
      expect(s.suggestSellTax(600000, market: 'TW', currency: 'TWD'), 1800);
    });

    test('使用者設定覆蓋市場預設;美股四捨五入到分', () {
      const s = InvestmentSettings(feeRate: 0.001, feeMin: 3);
      expect(s.suggestFee(2345.67, market: 'US', currency: 'USD'), 3);
      expect(s.suggestFee(12345.67, market: 'US', currency: 'USD'), 12.35);
    });

    test('encode/parse round trip 只保留有值的 key', () {
      const s = InvestmentSettings(market: 'tw', feeRate: 0.001425, reinvestDividends: true, settlementAccountId: 'acc');
      final parsed = InvestmentSettings.parse(s.encode());
      // 市場代碼解析時一律轉大寫
      expect(parsed.toJson(), {
        'market': 'TW',
        'feeRate': 0.001425,
        'reinvestDividends': true,
        'settlementAccountId': 'acc',
      });
      expect(InvestmentSettings.empty.encode(), isNull);
      expect(InvestmentSettings.parse('not json').isEmpty, isTrue);
    });
  });

  group('stockTradeTxFields(對齊 Cloud snapshot_mutator.stock_trade_tx_fields)', () {
    test('同幣別買進:本體 + feeAmount', () {
      final f = stockTradeTxFields(tradeType: 'buy', shares: 1000, price: 600, fee: 855, tax: 0,
          securityCurrency: 'TWD', settlementCurrency: 'TWD');
      expect(f.amount, 600000);
      expect(f.feeAmount, 855);
      expect(f.toAmount, isNull);
      expect(f.discountAmount, isNull);
    });

    test('同幣別賣出:本體 + discountAmount(手續費+稅)', () {
      final f = stockTradeTxFields(tradeType: 'sell', shares: 400, price: 700, fee: 399, tax: 840,
          securityCurrency: 'TWD', settlementCurrency: 'TWD');
      expect(f.amount, 280000);
      expect(f.discountAmount, 1239);
    });

    test('跨幣別:缺 settlementAmount 拋錯;買進 amount=交割金額、toAmount=成本', () {
      expect(
        () => stockTradeTxFields(tradeType: 'buy', shares: 10, price: 200, fee: 5, tax: 0,
            securityCurrency: 'USD', settlementCurrency: 'TWD'),
        throwsA(isA<StockTradeSettlementAmountRequired>()),
      );
      final buy = stockTradeTxFields(tradeType: 'buy', shares: 10, price: 200, fee: 5, tax: 0,
          securityCurrency: 'USD', settlementCurrency: 'TWD', settlementAmount: 64500);
      expect(buy.amount, 64500);
      expect(buy.toAmount, 2005);
      expect(buy.feeAmount, isNull);
      final sell = stockTradeTxFields(tradeType: 'sell', shares: 10, price: 250, fee: 5, tax: 1,
          securityCurrency: 'USD', settlementCurrency: 'TWD', settlementAmount: 79000);
      expect(sell.amount, 2494);
      expect(sell.toAmount, 79000);
    });

    test('stockTradeAmount', () {
      expect(stockTradeAmount(tradeType: 'buy', shares: 1000, price: 600, fee: 855, tax: 0), 600855);
      expect(stockTradeAmount(tradeType: 'sell', shares: 400, price: 700, fee: 399, tax: 840), 278761);
      expect(stockTradeAmount(tradeType: 'stock_dividend', shares: 10, price: 0, fee: 0, tax: 0), 0);
    });
  });

  // 跟券商(永豐)對帳單核對的案例;Cloud tests/test_trade_fees.py、Web
  // investmentFees.test.ts 用同一組數字。
  group('台股費用對帳(三端共用案例)', () {
    test('標的類型:00 開頭 ETF、結尾 B 債券 ETF、其它普通股;非台股一律普通股', () {
      expect(securityKindOf('TW', '0050'), SecurityKind.etf);
      expect(securityKindOf('TW', '00878'), SecurityKind.etf);
      expect(securityKindOf('TW', '00631L'), SecurityKind.etf);
      expect(securityKindOf('TWO', '00679B'), SecurityKind.bondEtf);
      expect(securityKindOf('TW', '2330'), SecurityKind.stock);
      expect(securityKindOf('US', '0050'), SecurityKind.stock);
    });

    test('0050 買進 50 股 @97.45、手續費 6 → 價金捨去成 4,872,總成本 4,878', () {
      expect(InvestmentSettings.gross(50, 97.45, 'TWD'), 4872);
      expect(
          stockTradeAmount(
              tradeType: 'buy',
              shares: 50,
              price: 97.45,
              fee: 6,
              tax: 0,
              currency: 'TWD'),
          4878);
      final f = stockTradeTxFields(
          tradeType: 'buy',
          shares: 50,
          price: 97.45,
          fee: 6,
          tax: 0,
          securityCurrency: 'TWD',
          settlementCurrency: 'TWD');
      expect(f.amount, 4872);
      expect(f.feeAmount, 6);
    });

    test('0050 賣出 50 股 @112.40:ETF 稅率 0.1%,交易稅 5 元(5.62 捨去)', () {
      const s = InvestmentSettings();
      expect(s.sellTaxRateFor(market: 'TW', symbol: '0050'), 0.001);
      expect(
          s.suggestSellTax(5620, market: 'TW', symbol: '0050', currency: 'TWD'),
          5);
      // 普通股 0.3%、債券 ETF 免徵
      expect(
          s.suggestSellTax(5620, market: 'TW', symbol: '2330', currency: 'TWD'),
          16);
      expect(
          s.suggestSellTax(5620, market: 'TW', symbol: '00679B', currency: 'TWD'),
          0);
    });

    test('使用者只改普通股稅率時,ETF 仍用 ETF 預設稅率', () {
      const s = InvestmentSettings(sellTaxRate: 0.003);
      expect(s.sellTaxRateFor(market: 'TW', symbol: '0050'), 0.001);
      const custom = InvestmentSettings(etfSellTaxRate: 0.0005);
      expect(custom.sellTaxRateFor(market: 'TW', symbol: '0050'), 0.0005);
    });

    test('捨去前先清浮點殘渣:1000 × 600.1 = 600,100 而不是 600,099', () {
      expect(InvestmentSettings.gross(1000, 600.1, 'TWD'), 600100);
      expect(InvestmentSettings.gross(3, 10.005, 'USD'), 30.02);
    });

    test('預估變現淨值 = 毛市值 − 手續費(含最低) − 交易稅', () {
      const s = InvestmentSettings(feeDiscount: 0.6, feeMin: 1);
      final e = s.estimateSell(
          shares: 50,
          price: 112.40,
          market: 'TW',
          symbol: '0050',
          currency: 'TWD');
      // 5620 × 0.001425 × 0.6 = 4.8 → 4;稅 5620 × 0.001 = 5.62 → 5
      expect(e.gross, 5620);
      expect(e.fee, 4);
      expect(e.tax, 5);
      expect(e.net, 5611);
    });
  });
}
