// 交易同步 apply 路径的信用卡紅利回饋(v35 rewardRuleIds)缺键保留语义测试。
//
// 场景比照 transaction_refund_apply_test.dart 的套路:entity_serializer.dart
// 的 serializeTransaction 恒发 rewardRuleIds(即使 `[]`),但其它客户端(旧版
// App / 尚未支持这个字段的 partial update payload)可能不带这个键——apply
// 时必须用 containsKey 保护,不能把已有的勾选静默清空。
//
// 这条用 engine.pull('') 走真实 applyRemoteChange seam(public 入口),
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

  Future<int> seedLedger() {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '测试账本',
          monthStartDay: const Value(1),
        ));
  }

  test('(insert) 远端新增交易带 rewardRuleIds → 本地插入 rewardRuleIdsJson 有值', () async {
    final lid = await seedLedger();
    const txSyncId = 'tx-reward-1';

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: txSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': txSyncId,
        'type': 'expense',
        'amount': 100,
        'happenedAt': '2026-08-16T00:00:00Z',
        'rewardRuleIds': ['rule-a', 'rule-b'],
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(txSyncId);
    expect(tx, isNotNull);
    expect(tx!.rewardRuleIds, ['rule-a', 'rule-b']);
  });

  test('远端 upsert 省略 rewardRuleIds 键 → 本地已有的勾选仍保留', () async {
    final lid = await seedLedger();
    const txSyncId = 'tx-reward-2';

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 8, 16),
      syncId: txSyncId,
      rewardRuleIds: ['rule-a'],
    );

    // 远端推同 syncId 的 upsert,只改 amount,**不带** rewardRuleIds 键
    // (模拟旧版 App 的 partial update payload)
    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: txSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': txSyncId,
        'type': 'expense',
        'amount': 250,
        'happenedAt': '2026-08-16T00:00:00Z',
        // 注意:故意省略 rewardRuleIds
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(txSyncId);
    expect(tx, isNotNull);
    expect(tx!.amount, 250, reason: 'amount 应被远端更新');
    expect(tx.rewardRuleIds, ['rule-a'], reason: '缺键不应清空本地已有的回饋勾選');
  });

  test('远端 upsert 显式带空 rewardRuleIds([]) → 清空本地已有的勾选', () async {
    final lid = await seedLedger();
    const txSyncId = 'tx-reward-3';

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 8, 16),
      syncId: txSyncId,
      rewardRuleIds: ['rule-a'],
    );

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: txSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': txSyncId,
        'type': 'expense',
        'amount': 100,
        'happenedAt': '2026-08-16T00:00:00Z',
        'rewardRuleIds': <String>[],
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(txSyncId);
    expect(tx, isNotNull);
    expect(tx!.rewardRuleIds, isEmpty, reason: '显式空 list 应清空回饋勾選');
  });
}
