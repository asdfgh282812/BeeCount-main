// 股利實收估算(docs/changes/2026-09-28-stock-dividends.md)。數字跟 Cloud
// tests/test_stock_dividends.py、Web investmentDividend.test.ts 同一組——三端
// 規則必須一致。
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/models/investment_settings.dart';
import 'package:beecount/services/investment/dividend_estimate.dart';

void main() {
  test('台股未達二代健保門檻:只扣匯費', () {
    final est = estimateDividend(
        market: 'TW', currency: 'TWD', shares: 1000, cashPerShare: 7, settings: InvestmentSettings.empty);
    expect([est.gross, est.fee, est.tax, est.net], [7000, 10, 0, 6990]);
  });

  test('台股達門檻:二代健保捨去到整數', () {
    final est = estimateDividend(
        market: 'TW', currency: 'TWD', shares: 5000, cashPerShare: 5, settings: InvestmentSettings.empty);
    expect(est.gross, 25000);
    expect(est.tax, 527);
    expect(est.net, 25000 - 10 - 527);
  });

  test('使用者設定蓋過市場預設', () {
    final est = estimateDividend(
      market: 'TW',
      currency: 'TWD',
      shares: 5000,
      cashPerShare: 5,
      settings: const InvestmentSettings(dividendFeeFixed: 0, nhiSupplementRate: 0),
    );
    expect([est.fee, est.tax, est.net], [0, 0, 25000]);
  });

  test('美股預扣稅 + 股利手續費率', () {
    final est = estimateDividend(
      market: 'US',
      currency: 'USD',
      shares: 10,
      cashPerShare: 0.27,
      settings: const InvestmentSettings(dividendFeeRate: 0.1),
    );
    expect(est.gross, closeTo(2.7, 1e-9));
    expect(est.tax, closeTo(0.81, 1e-9));
    expect(est.fee, closeTo(0.27, 1e-9));
    expect(est.net, closeTo(1.62, 1e-9));
  });

  test('配股:截斷過的配股率先四捨五入到千分位再捨去', () {
    final est = estimateDividend(
        market: 'TW',
        currency: 'TWD',
        shares: 1000,
        cashPerShare: 0,
        stockPerShare: 0.04999999,
        settings: InvestmentSettings.empty);
    expect(est.stockShares, 50);
    expect(est.net, 0);
  });
}
