import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/utils/card_reward_calc.dart';

CardRewardRule _rule({
  double? capAmount,
  String rateType = 'percentage',
  double rateValue = 8,
  String rounding = 'round',
}) {
  return CardRewardRule(
    id: 1,
    accountId: 1,
    label: '海外實體8%',
    rateType: rateType,
    rateValue: rateValue,
    rounding: rounding,
    totalRounding: 'round',
    calcBasis: 'transaction',
    interval: 'billing_cycle',
    capAmount: capAmount,
    settlementType: 'manual',
    enabled: true,
    sortOrder: 0,
  );
}

Transaction _tx(int id, double amount, DateTime happenedAt) {
  return Transaction(
    id: id,
    ledgerId: 1,
    type: 'expense',
    amount: amount,
    happenedAt: happenedAt,
    excludeFromStats: false,
    excludeFromBudget: false,
    recurringOccurrenceOverridden: false,
    hasSplits: false,
    needsAccountAssignment: false,
  );
}

void main() {
  group('estimateCardRewardCumulative', () {
    test('週期總額不超過 capAmount,即使逐筆各自試算未達單筆上限', () {
      final rule = _rule(capAmount: 500);
      final txs = [
        _tx(1, 143, DateTime(2026, 8, 20)),
        _tx(2, 1334, DateTime(2026, 8, 21)),
        _tx(3, 2536, DateTime(2026, 8, 21)),
        _tx(4, 819, DateTime(2026, 8, 27)),
        _tx(5, 202, DateTime(2026, 8, 27)),
        _tx(6, 81, DateTime(2026, 8, 27)),
        _tx(7, 2691, DateTime(2026, 8, 27)),
      ];

      final result = estimateCardRewardCumulative(rule, txs);
      final total = result.values.fold(0.0, (a, b) => a + b);

      expect(total, 500);
      // 逐筆各自估算(未套用週期上限)加總會是 624.48,證明 bug 修正前會超過上限。
      final perTxUncapped =
          txs.fold(0.0, (a, t) => a + estimateCardRewardForRule(rule, t.amount));
      expect(perTxUncapped, closeTo(624.48, 0.001));
    });

    test('額度用盡後的交易估算回饋金為 0', () {
      final rule = _rule(capAmount: 100);
      final txs = [
        _tx(1, 1000, DateTime(2026, 8, 1)), // 8% = 80, cap 剩 20
        _tx(2, 1000, DateTime(2026, 8, 2)), // 只剩 20 額度
        _tx(3, 1000, DateTime(2026, 8, 3)), // 額度已用盡
      ];

      final result = estimateCardRewardCumulative(rule, txs);
      expect(result[1], 80);
      expect(result[2], 20);
      expect(result[3], 0);
    });

    test('無 capAmount 時等同逐筆各自估算加總', () {
      final rule = _rule(capAmount: null);
      final txs = [
        _tx(1, 100, DateTime(2026, 8, 1)),
        _tx(2, 200, DateTime(2026, 8, 2)),
      ];

      final result = estimateCardRewardCumulative(rule, txs);
      expect(result[1], 8);
      expect(result[2], 16);
    });
  });
}
