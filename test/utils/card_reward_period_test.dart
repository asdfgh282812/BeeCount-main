import 'package:flutter_test/flutter_test.dart';
import 'package:beecount/utils/card_reward_period.dart';

void main() {
  group('creditCardPaymentDueDate', () {
    test('繳款日晚於結帳日:同月的 paymentDueDay', () {
      final due = creditCardPaymentDueDate(DateTime(2026, 8, 5), 20);
      expect(due, DateTime(2026, 8, 20));
    });

    test('繳款日早於或等於結帳日:順延到下個月', () {
      final due = creditCardPaymentDueDate(DateTime(2026, 8, 20), 5);
      expect(due, DateTime(2026, 9, 5));
    });

    test('結帳日跨年:順延到下個月時年份進位', () {
      final due = creditCardPaymentDueDate(DateTime(2026, 12, 20), 5);
      expect(due, DateTime(2027, 1, 5));
    });
  });

  group('billingCycleOffsetForDate', () {
    // billingCyclePeriod 本身吃即時的 DateTime.now(),測試不寫死年份日期,
    // 改用 billingCyclePeriod 自己算出來的區間邊界反推——不管實際跑測試的
    // 那天是哪天都成立,不會隨時間推移變成 flaky test。
    test('本期(offset=0)內的日期回傳 0', () {
      final period = billingCyclePeriod(5, 0);
      final offset = billingCycleOffsetForDate(5, period.start);
      expect(offset, 0);
    });

    test('前一期的日期回傳 -1', () {
      final previous = billingCyclePeriod(5, -1);
      final offset = billingCycleOffsetForDate(5, previous.end);
      expect(offset, -1);
    });

    test('往前推多期一樣算得出來', () {
      final period = billingCyclePeriod(5, -6);
      final offset = billingCycleOffsetForDate(5, period.start);
      expect(offset, -6);
    });

    test('沒設 billingDay 一樣算得出涵蓋這天的週期(退化成自然月起算)', () {
      final period = billingCyclePeriod(null, 0);
      final offset = billingCycleOffsetForDate(null, period.end);
      expect(offset, 0);
    });
  });
}
