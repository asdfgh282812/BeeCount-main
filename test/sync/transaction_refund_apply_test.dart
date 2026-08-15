// 交易同步 apply 路径的退款关联(v34 refundOfSyncId)缺键保留语义测试。
//
// 场景比照 transaction_exclude_flags_apply_test.dart 的 D6 套路:refundOfId
// 只在有值时才发(entity_serializer.dart「有值才发」),旧版 App / 不涉及退款
// 的 partial update payload 不会带这个键——apply 时必须用 containsKey 保护,
// 不能把已有的退款关联静默清空。
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

  test('(insert) 远端新增交易带 refundOfId → 本地插入 refundOfSyncId 有值', () async {
    final lid = await seedLedger();
    const originalSyncId = 'tx-orig-1';
    const refundSyncId = 'tx-refund-1';

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: refundSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': refundSyncId,
        'type': 'income',
        'amount': 100,
        'happenedAt': '2026-06-18T00:00:00Z',
        'refundOfId': originalSyncId,
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(refundSyncId);
    expect(tx, isNotNull);
    expect(tx!.refundOfSyncId, originalSyncId);

    final refunds = await repo.getRefundsOf(originalSyncId);
    expect(refunds.map((r) => r.syncId), contains(refundSyncId));
  });

  test('远端 upsert 省略 refundOfId 键 → 本地已有的退款关联仍保留', () async {
    final lid = await seedLedger();
    const originalSyncId = 'tx-orig-2';
    const refundSyncId = 'tx-refund-2';

    // 本地先建一条已经带 refundOfSyncId 的退款交易
    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 100,
      happenedAt: DateTime(2026, 6, 18),
      syncId: refundSyncId,
      refundOfSyncId: originalSyncId,
    );

    // 远端推同 syncId 的 upsert,只改 amount,**不带** refundOfId 键
    // (模拟旧版 App 的 partial update payload)
    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: refundSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': refundSyncId,
        'type': 'income',
        'amount': 250,
        'happenedAt': '2026-06-18T00:00:00Z',
        // 注意:故意省略 refundOfId
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(refundSyncId);
    expect(tx, isNotNull);
    expect(tx!.amount, 250, reason: 'amount 应被远端更新');
    expect(tx.refundOfSyncId, originalSyncId, reason: '缺键不应清空本地已有的退款关联');
  });
}
