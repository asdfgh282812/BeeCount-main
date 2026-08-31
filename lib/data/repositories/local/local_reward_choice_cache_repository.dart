import 'dart:convert';

import 'package:drift/drift.dart' as d;

import '../../db.dart';
import '../reward_choice_cache_repository.dart';

/// 本地回饋規則學習快取 Repository 實作,基於 Drift。
///
/// 唯一性靠 migration 裡建的
/// `idx_reward_choice_caches_key(ledger_id, category_id, account_id)` 索引
/// 保證,但該索引是透過 raw SQL 建的,drift 的 `insertOnConflictUpdate`
/// 認不到這個 conflict target——改用「先查再決定 insert/update」。
class LocalRewardChoiceCacheRepository implements RewardChoiceCacheRepository {
  final BeeDatabase db;

  LocalRewardChoiceCacheRepository(this.db);

  Future<RewardChoiceCache?> _findRow({
    required int ledgerId,
    required int categoryId,
    required int accountId,
  }) {
    return (db.select(db.rewardChoiceCaches)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.categoryId.equals(categoryId) &
              t.accountId.equals(accountId)))
        .getSingleOrNull();
  }

  @override
  Future<List<String>?> getCachedRewardRuleIds({
    required int ledgerId,
    required int categoryId,
    required int accountId,
  }) async {
    final row = await _findRow(
        ledgerId: ledgerId, categoryId: categoryId, accountId: accountId);
    if (row == null) return null;
    final decoded = jsonDecode(row.rewardRuleIdsJson);
    if (decoded is! List) return const [];
    return decoded.map((e) => e.toString()).toList();
  }

  @override
  Future<void> upsertRewardChoice({
    required int ledgerId,
    required int categoryId,
    required int accountId,
    required List<String> rewardRuleIds,
  }) async {
    final now = DateTime.now();
    final json = jsonEncode(rewardRuleIds);
    final existing = await _findRow(
        ledgerId: ledgerId, categoryId: categoryId, accountId: accountId);
    if (existing == null) {
      await db.into(db.rewardChoiceCaches).insert(
            RewardChoiceCachesCompanion.insert(
              ledgerId: ledgerId,
              categoryId: categoryId,
              accountId: accountId,
              rewardRuleIdsJson: json,
              updatedAt: d.Value(now),
            ),
          );
    } else {
      await (db.update(db.rewardChoiceCaches)
            ..where((t) => t.id.equals(existing.id)))
          .write(RewardChoiceCachesCompanion(
        rewardRuleIdsJson: d.Value(json),
        updatedAt: d.Value(now),
      ));
    }
  }

  @override
  Future<void> clearRewardChoice({
    required int ledgerId,
    required int categoryId,
    required int accountId,
  }) async {
    await (db.delete(db.rewardChoiceCaches)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.categoryId.equals(categoryId) &
              t.accountId.equals(accountId)))
        .go();
  }
}
