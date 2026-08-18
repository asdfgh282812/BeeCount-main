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
}
