// 交易同步 apply 路径的跨幣別轉帳(v45 toAmount)测试,比照
// transaction_refund_apply_test.dart 的套路——用 engine.pull('') 走真实
// applyRemoteChange seam,FakeBeeCountCloudProvider.pushFakeChange 注入远端 change。
//
// 覆盖 design doc §4 三种情形:
//   1. insert 带 toAmount 键 → 直接写入
//   2. update 带 toAmount 键 → 直接写入(覆盖本地旧值)
//   3. update 缺 toAmount 键 + 本地是 transfer 且已有 toAmount + amount 变了
//      → 按舊 amount/舊 toAmount 比例縮放(跟 Cloud
//      sync_applier.py::_sync_to_amount_after_merge 同一个公式)

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

  test('(insert) 远端新增跨币别转账带 toAmount → 本地插入 toAmount 有值', () async {
    final lid = await seedLedger();
    const syncId = 'tx-transfer-1';

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'transfer',
        'amount': 4711,
        'happenedAt': '2026-08-29T00:00:00Z',
        'toAmount': 999.87,
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx, isNotNull);
    expect(tx!.toAmount, 999.87);
  });

  test('(update) 远端 upsert 带 toAmount 键 → 直接覆盖本地旧值', () async {
    final lid = await seedLedger();
    const syncId = 'tx-transfer-2';

    await repo.addTransaction(
      ledgerId: lid,
      type: 'transfer',
      amount: 4711,
      happenedAt: DateTime(2026, 8, 29),
      syncId: syncId,
      toAmount: 999.87,
    );

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'transfer',
        'amount': 4711,
        'happenedAt': '2026-08-29T00:00:00Z',
        'toAmount': 950.0, // 使用者在別的裝置手動改了轉入金額
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx!.toAmount, 950.0);
  });

  test('(update) 缺 toAmount 键但带新 amount → 按隐含汇率等比缩放(旧客户端只知道转出端)', () async {
    final lid = await seedLedger();
    const syncId = 'tx-transfer-3';

    // 本地既有:转出 4711(JPY),转入 999.87(TWD) → 隐含汇率 999.87/4711
    await repo.addTransaction(
      ledgerId: lid,
      type: 'transfer',
      amount: 4711,
      happenedAt: DateTime(2026, 8, 29),
      syncId: syncId,
      toAmount: 999.87,
    );

    // 远端(旧客户端)只改了转出金额,不带 toAmount 键
    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'transfer',
        'amount': 9422, // 恰好是原来的 2 倍
        'happenedAt': '2026-08-29T00:00:00Z',
        // 注意:故意省略 toAmount
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx!.amount, 9422);
    // 999.87 / 4711 * 9422 == 999.87 * 2
    expect(tx.toAmount, closeTo(999.87 * 2, 1e-6));
  });

  test('(update) 缺 toAmount 键 + 本地 toAmount 本来就是 null(同币别转账)→ 仍保持 null',
      () async {
    final lid = await seedLedger();
    const syncId = 'tx-transfer-4';

    await repo.addTransaction(
      ledgerId: lid,
      type: 'transfer',
      amount: 200,
      happenedAt: DateTime(2026, 8, 29),
      syncId: syncId,
    );

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'transfer',
        'amount': 300,
        'happenedAt': '2026-08-29T00:00:00Z',
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx!.amount, 300);
    expect(tx.toAmount, isNull);
  });
}
