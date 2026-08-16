// 週期性收支規則(v36 recurring_rule,對齐 BeeCount Cloud)同步 apply 路径测试。
//
// recurring_rule 是 ledger-scope 实体,跟 budget 同款走
// `projection.upsert_recurring_rule` 的全量 UPSERT 语义(不是 partial merge)
// ——见 lib/cloud/sync/entity_serializer.dart::serializeRecurringRule 的注释。
// App push 时永远带出规则的全部字段当前真值,所以这里测的是 full-replace
// upsert 行为,不是缺键保留。
//
// 生成的 occurrence 交易走既有 _applyTransactionChange 路径,这里也顺带测
// transaction payload 里新增的 recurringRuleId/recurringOccurrenceOverridden
// 两个键能正确落地。
//
// 用 engine.pull('') 走真实 applyRemoteChange seam(public 入口），
// FakeBeeCountCloudProvider.pushFakeChange 注入远端 change。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Value;

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

import '../cloud/sync/_fakes/fake_beecount_cloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late ChangeTracker changeTracker;
  late LocalRepository repo;
  late FakeBeeCountCloudProvider provider;
  late SyncEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    changeTracker = ChangeTracker(db);
    repo = LocalRepository(db, changeTracker: changeTracker);
    provider = FakeBeeCountCloudProvider();
    engine = SyncEngine(
      db: db,
      provider: provider,
      changeTracker: changeTracker,
      repo: repo,
    );
  });

  tearDown(() async => db.close());

  Future<int> seedLedger({String? syncId}) {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '测试账本',
          monthStartDay: const Value(1),
          syncId: Value(syncId),
        ));
  }

  test('(insert) 远端新增週期規則 → 本地插入且欄位齊全(含分类/账户 syncId 解析)', () async {
    final lid = await seedLedger(syncId: 'ledger-1');
    final catId = await repo.createCategory(name: '餐飲', kind: 'expense');
    await (db.update(db.categories)..where((c) => c.id.equals(catId)))
        .write(const CategoriesCompanion(syncId: Value('cat-1')));
    final accId =
        await repo.createAccount(ledgerId: lid, name: '現金', syncId: 'acc-1');

    provider.pushFakeChange(
      entityType: 'recurring_rule',
      entitySyncId: 'rule-1',
      ledgerId: 'ledger-1',
      payload: {
        'syncId': 'rule-1',
        'txType': 'expense',
        'amount': 100.0,
        'note': '房租',
        'categoryId': 'cat-1',
        'accountId': 'acc-1',
        'merchant': '房東',
        'tagIds': <String>['tag-a', 'tag-b'],
        'frequency': 'monthly',
        'interval': 1,
        'nextRunAt': '2026-01-01T00:00:00Z',
        'endAt': '2026-12-01T00:00:00Z',
        'enabled': true,
        'generatedUntilAt': '2026-06-01T00:00:00Z',
        'advancedRuleJson': {'type': 'monthly_day', 'day': 1},
        'rewardRuleIds': <String>['reward-1'],
      },
    );

    await engine.pull('');

    final rule = await repo.getRuleBySyncId('rule-1');
    expect(rule, isNotNull);
    expect(rule!.ledgerId, lid);
    expect(rule.type, 'expense');
    expect(rule.amount, 100.0);
    expect(rule.note, '房租');
    expect(rule.categoryId, catId);
    expect(rule.accountId, accId);
    expect(rule.merchant, '房東');
    expect(rule.tagSyncIds, ['tag-a', 'tag-b']);
    expect(rule.frequency, 'monthly');
    expect(rule.interval, 1);
    expect(rule.enabled, true);
    expect(rule.rewardRuleIds, ['reward-1']);
    expect(rule.advancedRuleJson, isNotNull);
  });

  test('遠端 upsert 全量覆蓋 → 本地欄位跟隨最新 payload(full-replace,非 partial merge)',
      () async {
    final lid = await seedLedger(syncId: 'ledger-2');

    // 本地先建一条規則,note='舊備註'、有 merchant、有 endAt。
    await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 50,
      note: '舊備註',
      merchant: '舊商家',
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime(2026, 1, 1),
      endAt: DateTime(2026, 6, 1),
    );
    final before = (await repo.getRulesByLedger(lid)).single;
    final syncId = before.syncId!;

    // 遠端推同 syncId 的 upsert,note/merchant/endAt 都沒帶(對照 full-replace
    // 語義,缺鍵會被當成清空,不是保留)。
    provider.pushFakeChange(
      entityType: 'recurring_rule',
      entitySyncId: syncId,
      ledgerId: 'ledger-2',
      payload: {
        'syncId': syncId,
        'txType': 'expense',
        'amount': 999.0,
        'frequency': 'monthly',
        'interval': 1,
        'nextRunAt': '2026-01-01T00:00:00Z',
        'enabled': true,
        // 故意省略 note / merchant / endAt / categoryId。
      },
    );

    await engine.pull('');

    final rule = await repo.getRuleBySyncId(syncId);
    expect(rule, isNotNull);
    expect(rule!.amount, 999.0);
    expect(rule.note, isNull, reason: 'full-replace 語義下缺鍵視為清空');
    expect(rule.merchant, isNull, reason: 'full-replace 語義下缺鍵視為清空');
    expect(rule.endAt, isNull, reason: 'full-replace 語義下缺鍵視為清空');
  });

  test('(delete) 遠端刪除規則 → 本地對應行被移除', () async {
    final lid = await seedLedger(syncId: 'ledger-3');
    await repo.createRule(
      ledgerId: lid,
      type: 'expense',
      amount: 10,
      frequency: 'monthly',
      interval: 1,
      nextRunAt: DateTime.now(),
    );
    final syncId = (await repo.getRulesByLedger(lid)).single.syncId!;

    provider.pushFakeChange(
      entityType: 'recurring_rule',
      entitySyncId: syncId,
      ledgerId: 'ledger-3',
      action: 'delete',
    );

    await engine.pull('');

    expect(await repo.getRuleBySyncId(syncId), isNull);
  });

  test('账本本地尚未就緒(ledgerId 對不到)→ 跳過,不建孤兒規則', () async {
    provider.pushFakeChange(
      entityType: 'recurring_rule',
      entitySyncId: 'rule-orphan',
      ledgerId: 'ledger-not-synced-yet',
      payload: {
        'syncId': 'rule-orphan',
        'txType': 'expense',
        'amount': 10.0,
        'frequency': 'monthly',
        'interval': 1,
        'nextRunAt': '2026-01-01T00:00:00Z',
        'enabled': true,
      },
    );

    await engine.pull('');

    expect(await repo.getRuleBySyncId('rule-orphan'), isNull);
  });

  test(
      '(transaction payload) 遠端 occurrence 交易帶 recurringRuleId/recurringOccurrenceOverridden → 正確落地',
      () async {
    await seedLedger(syncId: 'ledger-4');

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: 'tx-occurrence-1',
      ledgerId: 'ledger-4',
      payload: {
        'syncId': 'tx-occurrence-1',
        'type': 'expense',
        'amount': 100.0,
        'happenedAt': '2026-02-01T00:00:00Z',
        'ledgerSyncId': 'ledger-4',
        'categoryName': null,
        'categoryKind': null,
        'accountName': '',
        'accountId': '',
        'fromAccountName': '',
        'fromAccountId': '',
        'toAccountName': '',
        'toAccountId': '',
        'recurringRuleId': 'rule-abc',
        'recurringOccurrenceOverridden': true,
      },
    );

    await engine.pull('');

    final tx = await (db.select(db.transactions)
          ..where((t) => t.syncId.equals('tx-occurrence-1')))
        .getSingle();
    expect(tx.recurringRuleId, 'rule-abc');
    expect(tx.recurringOccurrenceOverridden, isTrue);
  });
}
