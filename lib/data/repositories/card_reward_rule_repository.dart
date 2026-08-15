import 'package:drift/drift.dart' as d;

import '../db.dart';

/// 信用卡紅利回饋規則 Repository 接口。
///
/// user-global 实体(同 account/category/tag 那组白名单,不挂 ledgerId)。
/// 字段对照 BeeCount Cloud `sync_applier.py` 的
/// `_MergeSpec["card_reward_rule"]`,详见 [CardRewardRules] 表定义注释。
abstract class CardRewardRuleRepository {
  /// 创建一条回饋规则。[accountId]/[rateValue] 必填,其余对照 server 端
  /// `WriteCardRewardRuleCreateRequest` 的默认值。[syncId] 可选,pull-apply
  /// 路径显式塞对端 id,UI 建立走 auto v4。
  Future<int> createCardRewardRule({
    required int accountId,
    required String label,
    List<String>? categoryIds,
    String rateType = 'percentage',
    required double rateValue,
    String rounding = 'round',
    String totalRounding = 'round',
    String calcBasis = 'transaction_date',
    String interval = 'billing_cycle',
    double? minSpendThreshold,
    double? minTxAmount,
    double? capAmount,
    String? capSharedKey,
    DateTime? startsAt,
    DateTime? endsAt,
    String settlementType = 'manual',
    int? settlementDays,
    int? settlementMonthOffset,
    int? settlementDayOfMonth,
    int? rewardAccountId,
    String? note,
    bool enabled = true,
    int sortOrder = 0,
    String? syncId,
  });

  /// 更新一条回饋规则(整表单式覆盖,不是 partial patch——调用方需自行传入
  /// 想保留的既有值)。[companion] 直接用 drift 的 [d.Value] 语义:
  /// `Value(x)` = 写入 x(可以是 null,代表清空该栏位),
  /// `Value.absent()` = 不动这个栏位。
  Future<void> updateCardRewardRule(int id, CardRewardRulesCompanion companion);

  /// 删除一条回饋规则(硬删除,本地无历史关联顾虑——server 端软删逻辑只在
  /// 云端 `rule_has_history` 判断,详见 `card_reward_rule_editor_page.dart`
  /// 的 locked 提示)。
  Future<void> deleteCardRewardRule(int id);

  Future<CardRewardRule?> getCardRewardRuleById(int id);
  Future<CardRewardRule?> getCardRewardRuleBySyncId(String syncId);

  /// 某帐户下的全部回饋规则(含已停用),按 sortOrder 排序。
  Future<List<CardRewardRule>> getCardRewardRulesForAccount(int accountId);
  Stream<List<CardRewardRule>> watchCardRewardRulesForAccount(int accountId);

  /// 批量更新排序(拖曳排序用)。
  Future<void> updateCardRewardRuleSortOrders(
      List<({int id, int sortOrder})> updates);
}
