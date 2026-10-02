import 'package:beecount/models/investment_settings.dart';
import 'package:beecount/services/investment/stock_dca.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stockDcaOccurrenceIds matches Cloud stock_dca_occurrence_ids', () {
    // 跟 BeeCount Cloud tests/test_recurring_stock_dca.py
    // test_stock_dca_occurrence_ids_are_stable 同一組固定值。
    final ids = stockDcaOccurrenceIds(
        'rule-abc', DateTime.utc(2026, 10, 1, 1, 0));
    expect(ids.txSyncId, 'd16236f8-2b7d-5b7e-9efd-bdaf3378b3ad');
    expect(ids.tradeSyncId, '733552aa-0945-51af-9a0d-7f3c7a571135');
    // 本地時間 / 毫秒不影響結果
    final local = DateTime.utc(2026, 10, 1, 1, 0, 0, 999).toLocal();
    expect(stockDcaOccurrenceIds('rule-abc', local).txSyncId, ids.txSyncId);
  });

  group('stockDcaOrder(對齊 Cloud trade_fees.stock_dca_order / Web stockDcaOrder)',
      () {
    const fixedFee1 =
        InvestmentSettings(feeRate: 0, feeDiscount: 1, feeMin: 1);

    test('台股整數股:券商範例 3,000/月、手續費 1 元', () {
      for (final (price, shares, total) in [
        (150.0, 19.0, 2851.0),
        (100.0, 29.0, 2901.0),
        (200.0, 14.0, 2801.0),
      ]) {
        final o = stockDcaOrder(
            amount: 3000,
            price: price,
            market: 'TW',
            currency: 'TWD',
            feeSettings: fixedFee1)!;
        expect((o.shares, o.gross, o.fee, o.total),
            (shares, shares * price, 1.0, total));
      }
    });

    test('台股預設費率:3,000 @97.45 → 30 股、價金 2,923 + 手續費 20', () {
      final o = stockDcaOrder(
          amount: 3000,
          price: 97.45,
          market: 'TW',
          currency: 'TWD',
          feeSettings: const InvestmentSettings().resolvedFor('TW'))!;
      expect((o.shares, o.gross, o.fee, o.total), (30.0, 2923.0, 20.0, 2943.0));
    });

    test('實際手續費較低時用剩下的錢多買;買不起 1 股回 null', () {
      final tw = const InvestmentSettings().resolvedFor('TW');
      expect(
          stockDcaOrder(
                  amount: 1000,
                  price: 10,
                  market: 'TWO',
                  currency: 'TWD',
                  feeSettings: tw)!
              .shares,
          98);
      final o = stockDcaOrder(
          amount: 1000,
          price: 10,
          market: 'TW',
          currency: 'TWD',
          feeSettings:
              const InvestmentSettings(feeRate: 0.1, feeDiscount: 1, feeMin: 0))!;
      expect((o.shares, o.total), (90.0, 990.0));
      expect(
          stockDcaOrder(
              amount: 100,
              price: 95,
              market: 'TW',
              currency: 'TWD',
              feeSettings: tw),
          isNull);
    });

    test('美股碎股:金額全部買進、手續費另計', () {
      final o = stockDcaOrder(
          amount: 100,
          price: 450,
          market: 'US',
          currency: 'USD',
          feeSettings: const InvestmentSettings().resolvedFor('US'))!;
      expect(o.shares, closeTo(100 / 450, 1e-12));
      expect((o.gross, o.fee), (100.0, 0.25));
      expect(stockDcaWholeShares('two'), isTrue);
      expect(stockDcaWholeShares('US'), isFalse);
    });
  });
}
