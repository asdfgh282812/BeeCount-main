import '../data/db.dart';

/// 信用卡紅利回饋的前端估算公式,供記帳表單/交易詳情卡/帳戶回饋明細頁共用。
///
/// 純前端估算,不 call server——真正入帳金額仍由 BeeCount Cloud 排程計算
/// (門檻/上限/共同上限群組等跨交易邏輯只有 server 端看得到完整資料)。
double applyCardRewardRounding(double value, String rounding) {
  switch (rounding) {
    case 'floor':
      return (value * 100).floorToDouble() / 100;
    case 'ceil':
      return (value * 100).ceilToDouble() / 100;
    case 'keep':
      return value;
    case 'round':
    default:
      return (value * 100).roundToDouble() / 100;
  }
}

/// 單一規則對單筆交易金額(已取絕對值)的估算回饋金。
double estimateCardRewardForRule(CardRewardRule rule, double amount) {
  if (amount.abs() <= 0) return 0;
  double contribution;
  if (rule.rateType == 'fixed_amount') {
    contribution = rule.rateValue;
  } else {
    final raw = amount.abs() * rule.rateValue / 100;
    contribution = applyCardRewardRounding(raw, rule.rounding);
  }
  if (rule.capAmount != null && contribution > rule.capAmount!) {
    contribution = rule.capAmount!;
  }
  return contribution;
}

/// 多條規則加總(記帳表單勾選多條規則時使用)。
double estimateCardRewardTotal(List<CardRewardRule> rules, double amount) {
  if (rules.isEmpty || amount.abs() <= 0) return 0;
  var total = 0.0;
  for (final rule in rules) {
    total += estimateCardRewardForRule(rule, amount);
  }
  return total;
}

/// 前端估算單筆交易的入帳日期,供紅利回饋明細頁的「將於 X/X 入帳」標籤用。
/// `manual` 沒有可預測的排程,回傳 null(呼叫端應隱藏標籤或顯示「手動入帳」)。
/// 跟真正入帳金額一樣,這只是估算——server 端排程才是準的。
DateTime? estimateCardRewardSettlementDate({
  required CardRewardRule rule,
  required DateTime happenedAt,
  required DateTime periodEnd,
}) {
  switch (rule.settlementType) {
    // immediate_after_tx 现在也带「天数」(0=当天,1=隔天...),語意上跟
    // after_posting_date 算法一致,只是欄位分開給使用者選——沒設天數的舊資料
    // 一律當 0(=消費當天入帳,對齊改動前的行為)。
    case 'immediate_after_tx':
    case 'after_posting_date':
      return happenedAt.add(Duration(days: rule.settlementDays ?? 0));
    case 'period_end':
      var year = periodEnd.year;
      var month = periodEnd.month + (rule.settlementMonthOffset ?? 0);
      while (month > 12) {
        month -= 12;
        year += 1;
      }
      while (month <= 0) {
        month += 12;
        year -= 1;
      }
      final daysInMonth = DateTime(year, month + 1, 0).day;
      final day = (rule.settlementDayOfMonth ?? periodEnd.day).clamp(
        1,
        daysInMonth,
      );
      return DateTime(year, month, day);
    case 'manual':
    default:
      return null;
  }
}
