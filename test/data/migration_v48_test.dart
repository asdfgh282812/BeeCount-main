/// v48 迁移(「建議」分頁回饋學習快取 + 交易排序索引):
/// - 新表 reward_choice_caches(ledger_id, category_id, account_id,
///   reward_rule_ids_json, updated_at),唯一索引
///   idx_reward_choice_caches_key(ledger_id, category_id, account_id)。
/// - 新索引 idx_transactions_ledger_type_happened(ledger_id, type,
///   happened_at)——之前 transactions 只有 sync_id 一个索引,建議分頁排序
///   查詢 + 既有 note/amount 聚合查詢都是全表掃描。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';

void main() {
  late BeeDatabase db;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('schemaVersion >= 48', () {
    expect(db.schemaVersion, greaterThanOrEqualTo(48));
  });

  test('v48 schema:reward_choice_caches 表存在,所有列就位', () async {
    final cols =
        await db.customSelect("PRAGMA table_info(reward_choice_caches)").get();
    expect(cols, isNotEmpty,
        reason: 'reward_choice_caches 表必须存在(v48 onCreate / onUpgrade 创建)');
    final names = cols.map((r) => r.read<String>('name')).toSet();
    expect(
        names,
        containsAll([
          'id',
          'ledger_id',
          'category_id',
          'account_id',
          'reward_rule_ids_json',
          'updated_at',
        ]));
  });

  test('idx_reward_choice_caches_key 唯一索引生效:同組合重複 insert 抛错',
      () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    await db.into(db.rewardChoiceCaches).insert(
          RewardChoiceCachesCompanion.insert(
            ledgerId: 1,
            categoryId: 10,
            accountId: 20,
            rewardRuleIdsJson: '["a"]',
          ),
        );
    await expectLater(
      db.into(db.rewardChoiceCaches).insert(
            RewardChoiceCachesCompanion.insert(
              ledgerId: 1,
              categoryId: 10,
              accountId: 20,
              rewardRuleIdsJson: '["b"]',
            ),
          ),
      throwsA(anything),
    );
  });

  test('reward_choice_caches 寫入並讀回', () async {
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
    final id = await db.into(db.rewardChoiceCaches).insert(
          RewardChoiceCachesCompanion.insert(
            ledgerId: 1,
            categoryId: 10,
            accountId: 20,
            rewardRuleIdsJson: '["rule-1","rule-2"]',
          ),
        );
    final row = await (db.select(db.rewardChoiceCaches)
          ..where((t) => t.id.equals(id)))
        .getSingle();
    expect(row.rewardRuleIdsJson, '["rule-1","rule-2"]');
  });

  test('idx_transactions_ledger_type_happened 索引存在', () async {
    final indexes = await db
        .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'transactions'")
        .get();
    final names = indexes.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('idx_transactions_ledger_type_happened'));
  });

  test('idx_reward_choice_caches_key 索引存在', () async {
    final indexes = await db
        .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'reward_choice_caches'")
        .get();
    final names = indexes.map((r) => r.read<String>('name')).toSet();
    expect(names, contains('idx_reward_choice_caches_key'));
  });
}
