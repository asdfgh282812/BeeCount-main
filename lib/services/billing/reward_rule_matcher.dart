import '../../data/db.dart';

/// 用「互相包含」模糊比對 SwipeSmart 建議的規則名稱到本地目前生效中的
/// [CardRewardRule.label] 清單,剛好一筆命中才採用(design 2026-09-18 §2:
/// 不猜、不取分數最高/回饋最多那條,0 筆或多筆命中一律回傳 null,交易照常
/// 建立,只是沒有回饋)。
///
/// 比對規則:小寫 + trim 正規化後,`label.contains(target) || target.contains(label)`。
CardRewardRule? matchUniqueRewardRuleByLabel(
  String swipesmartRuleName,
  List<CardRewardRule> effectiveRules,
) {
  final target = swipesmartRuleName.toLowerCase().trim();
  if (target.isEmpty) return null;

  final matches = effectiveRules.where((r) {
    final label = r.label.toLowerCase().trim();
    if (label.isEmpty) return false;
    return label.contains(target) || target.contains(label);
  }).toList();

  return matches.length == 1 ? matches.first : null;
}

/// 「目前生效中」的判定:`enabled == true` 且在 [startsAt]/[endsAt] 區間內,
/// 邏輯同 `card_reward_rule_selector.dart` 的 `_eligible`。
List<CardRewardRule> effectiveRewardRules(List<CardRewardRule> all) {
  final now = DateTime.now();
  return all.where((r) {
    if (!r.enabled) return false;
    if (r.startsAt != null && r.startsAt!.isAfter(now)) return false;
    if (r.endsAt != null && r.endsAt!.isBefore(now)) return false;
    return r.syncId != null;
  }).toList();
}
