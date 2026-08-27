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

/// 單一規則在「一整個週期」內、依交易發生時間由舊到新依序試算的回饋金——
/// [estimateCardRewardForRule] 只對單筆交易金額套用 [CardRewardRule.capAmount],
/// 週期內多筆交易各自試算再加總會忽略彼此已經用掉多少額度,導致週期總額超過
/// 設定的上限(帳戶頁/明細頁的彙總卡片曾經因此顯示超過上限的金額)。這裡讓
/// 額度隨交易累積扣減,總額保證不超過 capAmount,對齊 Server 端排程的計算
/// 方式。回傳 {交易 id: 該筆的估算回饋金},呼叫端加總即為週期 totalReward。
///
/// [transactionsAscending] 必須已按 happenedAt 由舊到新排序——呼叫端如果是
/// 由新到舊排序的清單,要先反轉/重新排序再傳進來。
Map<int, double> estimateCardRewardCumulative(
  CardRewardRule rule,
  List<Transaction> transactionsAscending,
) {
  final result = <int, double>{};
  var cumulative = 0.0;
  for (final tx in transactionsAscending) {
    final amount = tx.amount.abs();
    if (amount <= 0) {
      result[tx.id] = 0;
      continue;
    }
    double contribution;
    if (rule.rateType == 'fixed_amount') {
      contribution = rule.rateValue;
    } else {
      contribution =
          applyCardRewardRounding(amount * rule.rateValue / 100, rule.rounding);
    }
    if (rule.capAmount != null) {
      final remaining = rule.capAmount! - cumulative;
      contribution = contribution <= 0
          ? 0
          : (remaining <= 0
              ? 0
              : (contribution > remaining ? remaining : contribution));
    }
    cumulative += contribution;
    result[tx.id] = contribution;
  }
  return result;
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
