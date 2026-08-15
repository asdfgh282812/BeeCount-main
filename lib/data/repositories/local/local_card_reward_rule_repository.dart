import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';

import '../../db.dart';
import '../card_reward_rule_repository.dart';

/// 本地信用卡紅利回饋規則 Repository 实现,基于 Drift。
///
/// 不直接挂 ChangeTracker——同 [LocalTagRepository] 的分工,changeTracker
/// 记录在 LocalRepository 包装层(见该文件 card_reward_rule 相关方法)。
class LocalCardRewardRuleRepository implements CardRewardRuleRepository {
  static const _uuid = Uuid();
  final BeeDatabase db;

  LocalCardRewardRuleRepository(this.db);

  String? _encodeStringList(List<String>? values) {
    if (values == null) return null;
    return jsonEncode(values);
  }

  @override
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
  }) async {
    final now = DateTime.now();
    return db.into(db.cardRewardRules).insert(
          CardRewardRulesCompanion.insert(
            accountId: accountId,
            label: label,
            categoryIdsJson: d.Value(_encodeStringList(categoryIds)),
            rateType: d.Value(rateType),
            rateValue: rateValue,
            rounding: d.Value(rounding),
            totalRounding: d.Value(totalRounding),
            calcBasis: d.Value(calcBasis),
            interval: d.Value(interval),
            minSpendThreshold: d.Value(minSpendThreshold),
            minTxAmount: d.Value(minTxAmount),
            capAmount: d.Value(capAmount),
            capSharedKey: d.Value(capSharedKey),
            startsAt: d.Value(startsAt),
            endsAt: d.Value(endsAt),
            settlementType: d.Value(settlementType),
            settlementDays: d.Value(settlementDays),
            settlementMonthOffset: d.Value(settlementMonthOffset),
            settlementDayOfMonth: d.Value(settlementDayOfMonth),
            rewardAccountId: d.Value(rewardAccountId),
            note: d.Value(note),
            enabled: d.Value(enabled),
            sortOrder: d.Value(sortOrder),
            syncId: d.Value(syncId ?? _uuid.v4()),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
          ),
        );
  }

  @override
  Future<void> updateCardRewardRule(
      int id, CardRewardRulesCompanion companion) async {
    await (db.update(db.cardRewardRules)..where((t) => t.id.equals(id)))
        .write(companion.copyWith(updatedAt: d.Value(DateTime.now())));
  }

  @override
  Future<void> deleteCardRewardRule(int id) async {
    await (db.delete(db.cardRewardRules)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<CardRewardRule?> getCardRewardRuleById(int id) async {
    return (db.select(db.cardRewardRules)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  @override
  Future<CardRewardRule?> getCardRewardRuleBySyncId(String syncId) async {
    return (db.select(db.cardRewardRules)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingleOrNull();
  }

  @override
  Future<List<CardRewardRule>> getCardRewardRulesForAccount(
      int accountId) async {
    return (db.select(db.cardRewardRules)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => d.OrderingTerm(expression: t.sortOrder)]))
        .get();
  }

  @override
  Stream<List<CardRewardRule>> watchCardRewardRulesForAccount(int accountId) {
    return (db.select(db.cardRewardRules)
          ..where((t) => t.accountId.equals(accountId))
          ..orderBy([(t) => d.OrderingTerm(expression: t.sortOrder)]))
        .watch();
  }

  @override
  Future<void> updateCardRewardRuleSortOrders(
      List<({int id, int sortOrder})> updates) async {
    await db.transaction(() async {
      for (final update in updates) {
        await (db.update(db.cardRewardRules)
              ..where((t) => t.id.equals(update.id)))
            .write(
                CardRewardRulesCompanion(sortOrder: d.Value(update.sortOrder)));
      }
    });
  }
}
