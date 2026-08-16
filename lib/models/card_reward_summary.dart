import '../data/db.dart';

/// 單一紅利回饋規則在其「本期」(依 [CardRewardRule.interval] 算出的週期)
/// 內的彙總——帳戶頁的紅利回饋分組卡片、明細頁共用同一份資料,數字保證對得上。
class CardRewardRuleSummary {
  final CardRewardRule rule;
  final DateTime periodStart;
  final DateTime periodEnd;

  /// 該週期內套用此規則的交易(已按 happenedAt 由新到舊排序)。
  final List<Transaction> transactions;

  /// 逐筆估算回饋金加總。
  final double totalReward;

  /// 逐筆消費金額(僅計 expense 類型)加總,用於「還差多少消費可達上限」投影。
  final double totalSpend;

  /// 自然月拆分:規則以「自然月」算上限,但檢視視窗(帳單週期)橫跨多個自然
  /// 月時,依自然月分開各自計算——每個元素是單一自然月的子彙總(該元素自己
  /// 的 [monthlyBreakdown] 恆為 null,不遞迴巢狀)。上層的 periodStart/End 仍
  /// 是整個檢視視窗的起訖,totalReward/totalSpend 是各自然月的加總。
  /// null 表示不需要拆分(規則以帳單週期為單位、或視窗本來就落在單一自然
  /// 月內)。見 [lib/utils/card_reward_period.dart] 的 splitPeriodByCalendarMonth。
  final List<CardRewardRuleSummary>? monthlyBreakdown;

  const CardRewardRuleSummary({
    required this.rule,
    required this.periodStart,
    required this.periodEnd,
    required this.transactions,
    required this.totalReward,
    required this.totalSpend,
    this.monthlyBreakdown,
  });
}
