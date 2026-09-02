/// 分期付款攤還演算法(對齐 BeeCount Cloud
/// `src/services/installment_amortization.py::compute_periods`,§2.12.1
/// Phase 1.5,`docs/superpowers/specs/2026-09-02-installment-tracking-design.md`
/// §2)。
///
/// 純函式、不依賴 Drift/Riverpod(比照 `lib/ai/` 的「provider-agnostic
/// 可獨立測試」原則)——給定分期參數,一次算出全部期數的本金/利息/合計明細。
///
/// **這裡明確採用的解讀約定**(移植自 Cloud 原始 docstring,逐字保留假設,
/// 不重新推導):
///
/// - [interestRate] 是**年利率**(如 0.06 = 6%/年)。[interestPeriod] 只決定
///   「每期利息按月計(rate/12,每期固定)還是按日計(rate/365 * 該期實際
///   天數,月份長短會讓每期利息略有差異)」,**不影響還款週期本身**——週期
///   一律按月(`_addMonths`),這是「計息方式」跟「還款頻率」兩個獨立維度裡,
///   只有前者被這個參數控制。
/// - 寬限期([gracePeriodMonths])對三種攤還方式一視同仁:前 g 期只還息不還本
///   (principal=0,interest=按當期利率乘當前餘額),從第 g+1 期才開始攤本金。
/// - 取整([roundAmounts])+ 餘數位置([remainderPosition]):這裡的「取整」是
///   取到整數金額(元),不是取到分。取整後每期本金加總可能跟 [totalAmount]
///   有 1 元以內的尾差,全部塞進 [remainderPosition] 指定的那一期
///   (first=第一個攤還期,跳過寬限期;last=最後一期),該期利息不變,合計
///   ([PeriodPlan.totalAmount])重新算 principal+interest。roundAmounts=false
///   時完全跳過取整/尾差調整,保留浮點數原始精度。
/// - `equal_installment`(等額本息)+ `interestPeriod='daily'` 時,標準年金
///   公式假設每期利率相同,但按日計息下每期天數不同(28/30/31 天),利率會
///   略有差異,沒有閉式解可以直接套。這裡用折現因子法廣義化:對每個攤還期
///   k 的利率 r_k,折現因子 `D_k = Π_{j<=k}(1+r_j)`,固定總付款 A 滿足
///   `sum(A / D_k for k) == 剩餘本金`,即 `A = 剩餘本金 / sum(1/D_k)`,算出 A
///   後逐期反推本金/利息(`interest_k = balance_{k-1} * r_k`,
///   `principal_k = A - interest_k`)。這是整份計算裡風險最高的一段數學延伸,
///   已在單元測試(`test/services/installment_amortization_test.dart`)裡鎖
///   對照值(搬自 Cloud `tests/test_installment_amortization.py`)——若跟
///   未來實際業務需求有出入,以這份 docstring 記錄的假設為準去調整測試,
///   **不要反過來改這裡的數學去湊測試**。
library;

import 'dart:math' as math;

const Set<String> kInstallmentRepaymentMethods = {
  'equal_installment',
  'equal_principal',
  'fixed_interest',
};
const Set<String> kInstallmentInterestPeriods = {'monthly', 'daily'};
const Set<String> kInstallmentRemainderPositions = {'first', 'last'};

/// 單期攤還明細。[totalAmount] 是 [principalAmount] + [interestAmount] 的
/// 衍生值,不獨立存。
class PeriodPlan {
  final int periodNo;
  final DateTime dueAt;
  final double principalAmount;
  final double interestAmount;

  const PeriodPlan({
    required this.periodNo,
    required this.dueAt,
    required this.principalAmount,
    required this.interestAmount,
  });

  double get totalAmount => principalAmount + interestAmount;

  PeriodPlan copyWith({double? principalAmount, double? interestAmount}) {
    return PeriodPlan(
      periodNo: periodNo,
      dueAt: dueAt,
      principalAmount: principalAmount ?? this.principalAmount,
      interestAmount: interestAmount ?? this.interestAmount,
    );
  }
}

/// 月份加減,等價 Cloud `snapshot_mutator.add_months`:超出當月天數時
/// clamp 到該月最後一天(如 1/31 + 1 個月 → 2/28 或 2/29,不是 3/3)。
///
/// [months] 可為負數(往回推)。Dart 的 `~/` 對負數是向零截斷(跟 Python `//`
/// 向負無窮取整不同),這裡先用 `%`(Dart 對正除數恆回傳非負餘數,等價
/// floor-mod)算出正規化月索引,再反推對應的年份偏移,避免負數月份時年份
/// 進位算錯(踩過一次:total=-1 時 `total ~/ 12 == 0`,但正確的年份偏移是
/// -1)。回傳值保留輸入的 UTC/本地時區旗標,避免呼叫端拿一個 UTC 輸入卻拿回
/// 本地時間的輸出。
DateTime addMonths(DateTime dt, int months) {
  final total = dt.month - 1 + months;
  final normalizedMonthIndex = total % 12; // 0..11,Dart 對正除數恆非負
  final year = dt.year + (total - normalizedMonthIndex) ~/ 12;
  final month = normalizedMonthIndex + 1;
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final day = dt.day < lastDayOfMonth ? dt.day : lastDayOfMonth;
  return dt.isUtc
      ? DateTime.utc(year, month, day, dt.hour, dt.minute, dt.second,
          dt.millisecond, dt.microsecond)
      : DateTime(year, month, day, dt.hour, dt.minute, dt.second,
          dt.millisecond, dt.microsecond);
}

double _roundUnit(double x) => x.roundToDouble();

List<double> _periodRates({
  required DateTime firstPeriodAt,
  required List<DateTime> dueDates,
  required String interestPeriod,
  required double interestRate,
}) {
  if (interestPeriod == 'monthly') {
    final r = interestRate / 12;
    return List<double>.filled(dueDates.length, r);
  }
  final rates = <double>[];
  var prev = addMonths(firstPeriodAt, -1);
  for (final d in dueDates) {
    final days = d.difference(prev).inDays;
    rates.add(interestRate / 365 * days);
    prev = d;
  }
  return rates;
}

/// 算出全部期數的攤還排程。輸入不合法時拋 [ArgumentError](呼叫端轉成使用者
/// 可見的表單錯誤)。
List<PeriodPlan> computeInstallmentPeriods({
  required double totalAmount,
  required int periods,
  required DateTime firstPeriodAt,
  String repaymentMethod = 'equal_principal',
  String interestPeriod = 'monthly',
  double interestRate = 0.0,
  bool roundAmounts = true,
  String remainderPosition = 'last',
  int gracePeriodMonths = 0,
}) {
  if (!kInstallmentRepaymentMethods.contains(repaymentMethod)) {
    throw ArgumentError('invalid repaymentMethod: $repaymentMethod');
  }
  if (!kInstallmentInterestPeriods.contains(interestPeriod)) {
    throw ArgumentError('invalid interestPeriod: $interestPeriod');
  }
  if (!kInstallmentRemainderPositions.contains(remainderPosition)) {
    throw ArgumentError('invalid remainderPosition: $remainderPosition');
  }
  if (periods < 1) {
    throw ArgumentError('periods must be >= 1');
  }
  if (totalAmount <= 0) {
    throw ArgumentError('totalAmount must be > 0');
  }
  if (interestRate < 0) {
    throw ArgumentError('interestRate must be >= 0');
  }
  if (!(gracePeriodMonths >= 0 && gracePeriodMonths < periods)) {
    throw ArgumentError('gracePeriodMonths must be >= 0 and < periods');
  }

  final dueDates = <DateTime>[
    firstPeriodAt,
    for (var k = 1; k < periods; k++) addMonths(firstPeriodAt, k),
  ];
  final rates = _periodRates(
    firstPeriodAt: firstPeriodAt,
    dueDates: dueDates,
    interestPeriod: interestPeriod,
    interestRate: interestRate,
  );

  final m = periods - gracePeriodMonths; // 攤還期數(不含寬限期)
  var balance = totalAmount;
  final results = <PeriodPlan>[];

  for (var k = 0; k < gracePeriodMonths; k++) {
    final interest = balance * rates[k];
    results.add(PeriodPlan(
      periodNo: k + 1,
      dueAt: dueDates[k],
      principalAmount: 0.0,
      interestAmount: interest,
    ));
  }

  if (repaymentMethod == 'equal_principal' ||
      repaymentMethod == 'fixed_interest') {
    final flatPrincipal = totalAmount / m;
    for (var i = 0; i < m; i++) {
      final k = gracePeriodMonths + i;
      final interest = repaymentMethod == 'fixed_interest'
          ? totalAmount * rates[k]
          : balance * rates[k];
      final principal = flatPrincipal;
      results.add(PeriodPlan(
        periodNo: k + 1,
        dueAt: dueDates[k],
        principalAmount: principal,
        interestAmount: interest,
      ));
      balance -= principal;
    }
  } else {
    // equal_installment(等額本息)
    final amortRates = rates.sublist(gracePeriodMonths, gracePeriodMonths + m);
    double payment;
    if (interestPeriod == 'monthly') {
      final r = amortRates.isNotEmpty ? amortRates[0] : 0.0;
      if (r == 0) {
        payment = balance / m;
      } else {
        final factor = math.pow(1 + r, m).toDouble();
        payment = balance * r * factor / (factor - 1);
      }
    } else {
      final discountFactors = <double>[];
      var cum = 1.0;
      for (final r in amortRates) {
        cum *= 1 + r;
        discountFactors.add(cum);
      }
      var sumInv = 0.0;
      for (final d in discountFactors) {
        sumInv += 1.0 / d;
      }
      payment = sumInv != 0 ? balance / sumInv : balance / m;
    }
    for (var i = 0; i < m; i++) {
      final k = gracePeriodMonths + i;
      final r = rates[k];
      final interest = balance * r;
      final principal = payment - interest;
      results.add(PeriodPlan(
        periodNo: k + 1,
        dueAt: dueDates[k],
        principalAmount: principal,
        interestAmount: interest,
      ));
      balance -= principal;
    }
  }

  if (roundAmounts) {
    return _applyRounding(
      results,
      totalAmount: totalAmount,
      gracePeriodMonths: gracePeriodMonths,
      remainderPosition: remainderPosition,
    );
  }
  return results;
}

List<PeriodPlan> _applyRounding(
  List<PeriodPlan> results, {
  required double totalAmount,
  required int gracePeriodMonths,
  required String remainderPosition,
}) {
  final rounded = [
    for (final r in results)
      PeriodPlan(
        periodNo: r.periodNo,
        dueAt: r.dueAt,
        principalAmount: _roundUnit(r.principalAmount),
        interestAmount: _roundUnit(r.interestAmount),
      ),
  ];
  var principalSum = 0.0;
  for (final r in rounded) {
    principalSum += r.principalAmount;
  }
  final diff = _roundUnit(totalAmount) - principalSum;
  if (diff != 0) {
    final amortIndices = [
      for (var i = 0; i < rounded.length; i++)
        if (rounded[i].periodNo > gracePeriodMonths) i,
    ];
    if (amortIndices.isNotEmpty) {
      final idx =
          remainderPosition == 'first' ? amortIndices.first : amortIndices.last;
      final adjusted = rounded[idx];
      rounded[idx] = adjusted.copyWith(
        principalAmount: adjusted.principalAmount + diff,
      );
    }
  }
  return rounded;
}
