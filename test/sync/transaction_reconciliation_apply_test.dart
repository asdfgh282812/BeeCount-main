// 交易同步 apply 路径的對帳模式(v37 reconciledAt/deferredPostingAt)缺键保留
// 语义测试。
//
// 跟 refundOfId 的「有值才发」不同:这两个欄位在 entity_serializer.dart 是
// **恒发**(见该文件註解——有明確的清空/取消確認動作,null 值必须能传达
// "清空"给对端)。所以这里要验证两件事:
//   1. payload 完全省略某个键(旧版 App / 尚未支持这两个字段的其它客户端)
//      → apply 时不覆盖本地已有值(containsKey 保护)。
//   2. payload 带键但值是 null(使用者主動取消確認/取消延後)→ 本地值真的
//      被清成 null,不是被 containsKey 保护误挡。
//
// 这条用 engine.pull('') 走真实 applyRemoteChange seam(public 入口),
// FakeBeeCountCloudProvider.pushFakeChange 注入远端 change,比照
// transaction_refund_apply_test.dart 的套路。

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

  test('(insert) 远端新增交易带 reconciledAt/deferredPostingAt → 本地插入两栏都有值',
      () async {
    final lid = await seedLedger();
    const syncId = 'tx-recon-insert-1';

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'expense',
        'amount': 100,
        'happenedAt': '2026-06-18T00:00:00Z',
        'reconciledAt': '2026-06-20T00:00:00Z',
        'deferredPostingAt': '2026-07-05T00:00:00Z',
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx, isNotNull);
    expect(tx!.reconciledAt, DateTime.parse('2026-06-20T00:00:00Z').toLocal());
    expect(tx.deferredPostingAt,
        DateTime.parse('2026-07-05T00:00:00Z').toLocal());
  });

  test('远端 upsert 省略 reconciledAt/deferredPostingAt 键 → 本地已有值仍保留',
      () async {
    final lid = await seedLedger();
    const syncId = 'tx-recon-2';

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          ledgerId: lid,
          type: 'expense',
          amount: 100,
          happenedAt: Value(DateTime(2026, 6, 18)),
          syncId: Value(syncId),
          reconciledAt: Value(DateTime(2026, 6, 20)),
          deferredPostingAt: Value(DateTime(2026, 7, 5)),
        ));

    // 远端推同 syncId 的 upsert,只改 amount,**不带** reconciledAt/
    // deferredPostingAt 键(模拟旧版 App 的 partial update payload)。
    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'expense',
        'amount': 250,
        'happenedAt': '2026-06-18T00:00:00Z',
        // 注意:故意省略 reconciledAt/deferredPostingAt
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx, isNotNull);
    expect(tx!.amount, 250, reason: 'amount 应被远端更新');
    expect(tx.reconciledAt, DateTime(2026, 6, 20), reason: '缺键不应清空本地已有的對帳確認');
    expect(tx.deferredPostingAt, DateTime(2026, 7, 5),
        reason: '缺键不应清空本地已有的延後入帳日');
  });

  test('远端 upsert 带 reconciledAt/deferredPostingAt 键但值是 null → 本地值被清空',
      () async {
    final lid = await seedLedger();
    const syncId = 'tx-recon-3';

    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          ledgerId: lid,
          type: 'expense',
          amount: 100,
          happenedAt: Value(DateTime(2026, 6, 18)),
          syncId: Value(syncId),
          reconciledAt: Value(DateTime(2026, 6, 20)),
          deferredPostingAt: Value(DateTime(2026, 7, 5)),
        ));

    // 使用者在另一台裝置取消確認/取消延後入帳:entity_serializer.dart 恒发
    // 这两个键,值是显式 null。
    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'expense',
        'amount': 100,
        'happenedAt': '2026-06-18T00:00:00Z',
        'reconciledAt': null,
        'deferredPostingAt': null,
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx, isNotNull);
    expect(tx!.reconciledAt, isNull, reason: '带键且值为 null 应清空對帳確認');
    expect(tx.deferredPostingAt, isNull, reason: '带键且值为 null 应清空延後入帳日');
  });
}
