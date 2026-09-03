/// `computeFeeDiscountNetAmount`——支出/收入手續費/折扣淨額公式,對齐
/// BeeCount Cloud `_compute_fee_discount_amount`(routers/write/_shared.py)。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/utils/amount_calculator.dart';

void main() {
  test('expense: amount = base + fee - discount', () {
    final r = computeFeeDiscountNetAmount(
      type: 'expense',
      baseAmount: 100,
      feeAmount: 5,
      discountAmount: 20,
    );
    expect(r, 85);
  });

  test('income: amount = base - fee + discount', () {
    final r = computeFeeDiscountNetAmount(
      type: 'income',
      baseAmount: 100,
      feeAmount: 5,
      discountAmount: 20,
    );
    expect(r, 115);
  });

  test('沒有手續費/折扣時淨額等於原始金額', () {
    final expense = computeFeeDiscountNetAmount(
      type: 'expense',
      baseAmount: 100,
      feeAmount: 0,
      discountAmount: 0,
    );
    final income = computeFeeDiscountNetAmount(
      type: 'income',
      baseAmount: 100,
      feeAmount: 0,
      discountAmount: 0,
    );
    expect(expense, 100);
    expect(income, 100);
  });

  test('折扣大於本金+手續費時淨額可為負(比照 Cloud 不額外擋)', () {
    final r = computeFeeDiscountNetAmount(
      type: 'expense',
      baseAmount: 10,
      feeAmount: 0,
      discountAmount: 50,
    );
    expect(r, -40);
  });

  test('浮點數安全:0.1 + 0.2 這類輸入不會有浮點漂移殘留', () {
    final r = computeFeeDiscountNetAmount(
      type: 'expense',
      baseAmount: 0.1,
      feeAmount: 0.2,
      discountAmount: 0,
    );
    expect(r, 0.3);
  });

  test('結果四捨五入到兩位小數', () {
    final r = computeFeeDiscountNetAmount(
      type: 'expense',
      baseAmount: 10.005,
      feeAmount: 0,
      discountAmount: 0,
    );
    expect(r, 10.01);
  });
}
