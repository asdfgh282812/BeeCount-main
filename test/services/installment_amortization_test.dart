// services.installment_amortization.computeInstallmentPeriods 的純函式單元
// 測試。
//
// 數值全部搬自 BeeCount Cloud
// `tests/test_installment_amortization.py` 的鎖定參考值(見
// `docs/superpowers/specs/2026-09-02-installment-tracking-design.md` §2 末尾
// 列的 6 組數值)——鎖住回歸,若這些數字變了,先確認是不是攤還公式本身改了
// (通常不該),而不是反過來改測試湊數字。

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/installment/installment_amortization.dart';

void main() {
  final first = DateTime.utc(2026, 1, 15);

  test('等額本金 + 無息:每期本金/利息平均攤分', () {
    final periods = computeInstallmentPeriods(
      totalAmount: 1200,
      periods: 12,
      firstPeriodAt: first,
      repaymentMethod: 'equal_principal',
      interestRate: 0.0,
    );
    expect(periods, hasLength(12));
    expect(periods.every((p) => p.principalAmount == 100.0), isTrue);
    expect(periods.every((p) => p.interestAmount == 0.0), isTrue);
    expect(periods.every((p) => p.totalAmount == 100.0), isTrue);
    expect(periods[0].dueAt, first);
    expect(periods[1].dueAt, DateTime.utc(2026, 2, 15));
    expect(periods[11].dueAt, DateTime.utc(2026, 12, 15));
  });

  test('等額本息 + monthly 12%:鎖定值(第1期本金95+利息12=107;第12期本金107+利息1)', () {
    final periods = computeInstallmentPeriods(
      totalAmount: 1200,
      periods: 12,
      firstPeriodAt: first,
      repaymentMethod: 'equal_installment',
      interestPeriod: 'monthly',
      interestRate: 0.12,
    );
    expect(periods, hasLength(12));
    expect(periods[0].principalAmount, 95.0);
    expect(periods[0].interestAmount, 12.0);
    expect(periods[0].totalAmount, 107.0);
    expect(periods[11].principalAmount, 107.0);
    expect(periods[11].interestAmount, 1.0);
    final principalSum =
        periods.fold<double>(0, (sum, p) => sum + p.principalAmount);
    expect(double.parse(principalSum.toStringAsFixed(2)), 1200.0);
  });

  test('固定利息 + monthly 12%:每期本金100+利息12=112(利息恆定,不隨餘額遞減)', () {
    final periods = computeInstallmentPeriods(
      totalAmount: 1200,
      periods: 12,
      firstPeriodAt: first,
      repaymentMethod: 'fixed_interest',
      interestPeriod: 'monthly',
      interestRate: 0.12,
    );
    expect(periods.every((p) => p.principalAmount == 100.0), isTrue);
    expect(periods.every((p) => p.interestAmount == 12.0), isTrue);
    expect(periods.every((p) => p.totalAmount == 112.0), isTrue);
  });

  test('寬限期 2 期:前2期只還息本金0,第3期起10期均攤(每期本金120),利息逐期遞減', () {
    final periods = computeInstallmentPeriods(
      totalAmount: 1200,
      periods: 12,
      firstPeriodAt: first,
      repaymentMethod: 'equal_principal',
      interestPeriod: 'monthly',
      interestRate: 0.12,
      gracePeriodMonths: 2,
    );
    expect(periods[0].principalAmount, 0.0);
    expect(periods[0].interestAmount, 12.0);
    expect(periods[1].principalAmount, 0.0);
    expect(periods[1].interestAmount, 12.0);
    expect(periods[2].principalAmount, 120.0);
    expect(periods[2].interestAmount, 12.0);
    expect(periods[3].interestAmount, 11.0);
    final principalSum =
        periods.fold<double>(0, (sum, p) => sum + p.principalAmount);
    expect(double.parse(principalSum.toStringAsFixed(2)), 1200.0);
  });

  test('等額本息 + daily 12%:鎖定值(第1期本金94+利息12=106,跟monthly版本95/12/107略有差異)', () {
    final periods = computeInstallmentPeriods(
      totalAmount: 1200,
      periods: 12,
      firstPeriodAt: first,
      repaymentMethod: 'equal_installment',
      interestPeriod: 'daily',
      interestRate: 0.12,
    );
    expect(periods, hasLength(12));
    expect(periods[0].principalAmount, 94.0);
    expect(periods[0].interestAmount, 12.0);
    expect(periods[0].totalAmount, 106.0);
    final principalSum =
        periods.fold<double>(0, (sum, p) => sum + p.principalAmount);
    expect(double.parse(principalSum.toStringAsFixed(2)), 1200.0);
  });

  test('remainderPosition=first vs last:1000元/3期尾差歸屬不同期', () {
    final firstVariant = computeInstallmentPeriods(
      totalAmount: 1000,
      periods: 3,
      firstPeriodAt: first,
      repaymentMethod: 'equal_principal',
      remainderPosition: 'first',
    );
    expect(firstVariant[0].principalAmount, 334.0);
    expect(firstVariant[1].principalAmount, 333.0);
    expect(firstVariant[2].principalAmount, 333.0);

    final lastVariant = computeInstallmentPeriods(
      totalAmount: 1000,
      periods: 3,
      firstPeriodAt: first,
      repaymentMethod: 'equal_principal',
      remainderPosition: 'last',
    );
    expect(lastVariant[0].principalAmount, 333.0);
    expect(lastVariant[1].principalAmount, 333.0);
    expect(lastVariant[2].principalAmount, 334.0);
  });

  test('roundAmounts=false 時完全跳過取整,保留原始浮點精度', () {
    final periods = computeInstallmentPeriods(
      totalAmount: 1000,
      periods: 3,
      firstPeriodAt: first,
      repaymentMethod: 'equal_principal',
      roundAmounts: false,
    );
    expect(periods[0].principalAmount, closeTo(1000 / 3, 1e-9));
    expect(periods[1].principalAmount, closeTo(1000 / 3, 1e-9));
    expect(periods[2].principalAmount, closeTo(1000 / 3, 1e-9));
  });

  group('輸入驗證:非法參數拋 ArgumentError', () {
    test('totalAmount <= 0', () {
      expect(
        () => computeInstallmentPeriods(
            totalAmount: 0, periods: 12, firstPeriodAt: first),
        throwsArgumentError,
      );
    });
    test('periods < 1', () {
      expect(
        () => computeInstallmentPeriods(
            totalAmount: 1200, periods: 0, firstPeriodAt: first),
        throwsArgumentError,
      );
    });
    test('gracePeriodMonths >= periods', () {
      expect(
        () => computeInstallmentPeriods(
          totalAmount: 1200,
          periods: 12,
          firstPeriodAt: first,
          gracePeriodMonths: 12,
        ),
        throwsArgumentError,
      );
    });
    test('repaymentMethod 不合法', () {
      expect(
        () => computeInstallmentPeriods(
          totalAmount: 1200,
          periods: 12,
          firstPeriodAt: first,
          repaymentMethod: 'bogus',
        ),
        throwsArgumentError,
      );
    });
    test('interestPeriod 不合法', () {
      expect(
        () => computeInstallmentPeriods(
          totalAmount: 1200,
          periods: 12,
          firstPeriodAt: first,
          interestPeriod: 'bogus',
        ),
        throwsArgumentError,
      );
    });
    test('remainderPosition 不合法', () {
      expect(
        () => computeInstallmentPeriods(
          totalAmount: 1200,
          periods: 12,
          firstPeriodAt: first,
          remainderPosition: 'bogus',
        ),
        throwsArgumentError,
      );
    });
    test('interestRate < 0', () {
      expect(
        () => computeInstallmentPeriods(
          totalAmount: 1200,
          periods: 12,
          firstPeriodAt: first,
          interestRate: -0.1,
        ),
        throwsArgumentError,
      );
    });
  });
}
