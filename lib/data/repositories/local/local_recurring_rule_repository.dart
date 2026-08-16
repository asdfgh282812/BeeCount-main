import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';

import '../../db.dart';

const _uuid = Uuid();

/// 週期性收支規則表([RecurringTransactions])的純本地 CRUD 輔助類。**不
/// 實現 [RecurringRuleRepository] 接口**——那個接口有好幾個方法(建規則當場
/// 批次生成 occurrence、「此記錄 vs 連同未來週期」編輯/刪除、視窗續產生)本
/// 質上要同時碰 [Transactions]/[Tags]/`changeTracker`,單一子倉庫拿不到那
/// 些依賴,實現直接放在 `LocalRepository`(同 budget/account 那組「複雜編排
/// 邏輯集中在 facade」的既有慣例,見
/// docs/CLOUD_SYNC_INTEGRATION.md §2「實際呼叫點在哪」)。這裡只提供
/// `LocalRepository` 拼裝時要用的低階單表操作。
class LocalRecurringRuleRepository {
  final BeeDatabase db;

  LocalRecurringRuleRepository(this.db);

  String? _encodeStringList(List<String> items) =>
      items.isEmpty ? null : jsonEncode(items);

  Future<int> createRule({
    required int ledgerId,
    required String type,
    required double amount,
    int? categoryId,
    int? accountId,
    int? fromAccountId,
    int? toAccountId,
    String? note,
    String? merchant,
    List<String> tagSyncIds = const [],
    List<String> rewardRuleSyncIds = const [],
    required String frequency,
    int interval = 1,
    Map<String, dynamic>? advancedRule,
    required DateTime nextRunAt,
    DateTime? endAt,
  }) async {
    return await db.into(db.recurringTransactions).insert(
          RecurringTransactionsCompanion.insert(
            syncId: d.Value(_uuid.v4()),
            ledgerId: ledgerId,
            type: type,
            amount: amount,
            categoryId: d.Value(categoryId),
            accountId: d.Value(accountId),
            fromAccountId: d.Value(fromAccountId),
            toAccountId: d.Value(toAccountId),
            note: d.Value(note),
            merchant: d.Value(merchant),
            tagSyncIdsJson: d.Value(_encodeStringList(tagSyncIds)),
            rewardRuleIdsJson: d.Value(_encodeStringList(rewardRuleSyncIds)),
            frequency: frequency,
            interval: d.Value(interval),
            advancedRuleJson:
                d.Value(advancedRule == null ? null : jsonEncode(advancedRule)),
            nextRunAt: nextRunAt,
            endAt: d.Value(endAt),
          ),
        );
  }

  /// 純欄位更新,不碰生成邏輯(供 `LocalRepository` 的編排方法呼叫)。只有
  /// 傳入非 null 的欄位才會被更新(partial update)。
  Future<void> updateRuleFields(
    int id, {
    String? type,
    double? amount,
    int? categoryId,
    bool clearCategoryId = false,
    int? accountId,
    bool clearAccountId = false,
    int? fromAccountId,
    bool clearFromAccountId = false,
    int? toAccountId,
    bool clearToAccountId = false,
    String? note,
    bool clearNote = false,
    String? merchant,
    bool clearMerchant = false,
    List<String>? tagSyncIds,
    List<String>? rewardRuleSyncIds,
    String? frequency,
    int? interval,
    Map<String, dynamic>? advancedRule,
    bool clearAdvancedRule = false,
    DateTime? nextRunAt,
    DateTime? endAt,
    bool clearEndAt = false,
    DateTime? generatedUntilAt,
    bool? enabled,
  }) async {
    await (db.update(db.recurringTransactions)..where((r) => r.id.equals(id)))
        .write(RecurringTransactionsCompanion(
      type: type != null ? d.Value(type) : const d.Value.absent(),
      amount: amount != null ? d.Value(amount) : const d.Value.absent(),
      categoryId: clearCategoryId
          ? const d.Value(null)
          : (categoryId != null ? d.Value(categoryId) : const d.Value.absent()),
      accountId: clearAccountId
          ? const d.Value(null)
          : (accountId != null ? d.Value(accountId) : const d.Value.absent()),
      fromAccountId: clearFromAccountId
          ? const d.Value(null)
          : (fromAccountId != null ? d.Value(fromAccountId) : const d.Value.absent()),
      toAccountId: clearToAccountId
          ? const d.Value(null)
          : (toAccountId != null ? d.Value(toAccountId) : const d.Value.absent()),
      note: clearNote ? const d.Value(null) : (note != null ? d.Value(note) : const d.Value.absent()),
      merchant: clearMerchant
          ? const d.Value(null)
          : (merchant != null ? d.Value(merchant) : const d.Value.absent()),
      tagSyncIdsJson:
          tagSyncIds != null ? d.Value(_encodeStringList(tagSyncIds)) : const d.Value.absent(),
      rewardRuleIdsJson: rewardRuleSyncIds != null
          ? d.Value(_encodeStringList(rewardRuleSyncIds))
          : const d.Value.absent(),
      frequency: frequency != null ? d.Value(frequency) : const d.Value.absent(),
      interval: interval != null ? d.Value(interval) : const d.Value.absent(),
      advancedRuleJson: clearAdvancedRule
          ? const d.Value(null)
          : (advancedRule != null ? d.Value(jsonEncode(advancedRule)) : const d.Value.absent()),
      nextRunAt: nextRunAt != null ? d.Value(nextRunAt) : const d.Value.absent(),
      endAt: clearEndAt ? const d.Value(null) : (endAt != null ? d.Value(endAt) : const d.Value.absent()),
      generatedUntilAt:
          generatedUntilAt != null ? d.Value(generatedUntilAt) : const d.Value.absent(),
      enabled: enabled != null ? d.Value(enabled) : const d.Value.absent(),
      updatedAt: d.Value(DateTime.now()),
    ));
  }

  Future<void> deleteRuleRow(int id) async {
    await (db.delete(db.recurringTransactions)..where((r) => r.id.equals(id))).go();
  }

  Future<RecurringTransaction?> getRuleById(int id) => (db.select(db.recurringTransactions)
        ..where((r) => r.id.equals(id)))
      .getSingleOrNull();

  Future<RecurringTransaction?> getRuleBySyncId(String syncId) =>
      (db.select(db.recurringTransactions)..where((r) => r.syncId.equals(syncId)))
          .getSingleOrNull();

  Future<List<RecurringTransaction>> getRulesByLedger(int ledgerId) =>
      (db.select(db.recurringTransactions)..where((r) => r.ledgerId.equals(ledgerId))).get();

  Future<List<RecurringTransaction>> getAllRulesForExport() =>
      db.select(db.recurringTransactions).get();

  Stream<List<RecurringTransaction>> watchRulesByLedger(int ledgerId) =>
      (db.select(db.recurringTransactions)..where((r) => r.ledgerId.equals(ledgerId))).watch();

  Future<int> getActiveRuleCountByAccount(int accountId) async {
    final rows = await (db.select(db.recurringTransactions)
          ..where((r) =>
              r.enabled.equals(true) &
              (r.accountId.equals(accountId) |
                  r.fromAccountId.equals(accountId) |
                  r.toAccountId.equals(accountId))))
        .get();
    return rows.length;
  }
}
