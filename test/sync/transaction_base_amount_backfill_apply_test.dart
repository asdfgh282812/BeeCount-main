// 交易同步 apply 路径的 v52 base_amount 自愈测试。
//
// 场景根因(见 docs/changes/2026-09-04-sync-base-amount-backfill.md):某些
// 历史 SyncChange 的 payload 只带了 feeAmount/discountAmount 却漏了
// baseAmount 键——「缺键不覆盖」语意下 base_amount 会永远停在 null,使用者
// 只能一笔一笔手动在 web 端重新触发同步。sync_engine_apply.dart 的
// _applyTransactionChange 改成:缺 baseAmount 键但 fee/discount 明显已启用
// (非 0)却查出本地/incoming 都没有 baseAmount 时,用必然正确的 amount 反推
// (computeBaseAmountFromNet)。
//
// 这条用 engine.pull('') 走真实 applyRemoteChange seam(同款
// transaction_exclude_flags_apply_test.dart 的 harness)。

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

  test('(update) 远端只带 feeAmount 漏 baseAmount 键 → 用 amount 反推补齐', () async {
    final lid = await seedLedger();
    const txSyncId = 'tx-base-1';

    // 本地已有一条交易(旧数据:创建于 App 支持手续费/折扣之前),
    // base_amount 一直是 null。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 2691,
      happenedAt: DateTime(2026, 9, 1),
      syncId: txSyncId,
    );

    // 远端 upsert:只带 amount/feeAmount/discountAmount,漏了 baseAmount 键
    // (模拟 Cloud 端某次历史写入没把 base_amount 塞进 payload_json)。
    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: txSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': txSyncId,
        'type': 'expense',
        'amount': 2691,
        'happenedAt': '2026-09-01T00:00:00Z',
        'feeAmount': 40,
        'discountAmount': 0,
        // 注意:故意省略 baseAmount 键
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(txSyncId);
    expect(tx, isNotNull);
    expect(tx!.feeAmount, 40);
    expect(tx.baseAmount, 2651,
        reason: 'baseAmount 缺键但 fee 已启用 → 用 amount-fee+discount 反推');
  });

  test('(insert) 远端新增交易只带 discountAmount 漏 baseAmount 键 → 反推补齐', () async {
    final lid = await seedLedger();
    const txSyncId = 'tx-base-2';

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: txSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': txSyncId,
        'type': 'income',
        'amount': 980,
        'happenedAt': '2026-09-01T00:00:00Z',
        'discountAmount': 20,
        // 注意:故意省略 baseAmount 键
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(txSyncId);
    expect(tx, isNotNull);
    // income: amount = base - fee + discount → base = amount + fee - discount
    expect(tx!.baseAmount, 960);
  });

  test('(update) fee/discount 均为 0 且漏 baseAmount 键 → 不强行反推,保持 null', () async {
    final lid = await seedLedger();
    const txSyncId = 'tx-base-3';

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 9, 1),
      syncId: txSyncId,
    );

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: txSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': txSyncId,
        'type': 'expense',
        'amount': 100,
        'happenedAt': '2026-09-01T00:00:00Z',
        // 没有 fee/discount 键,普通交易本来就不该有 baseAmount。
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(txSyncId);
    expect(tx, isNotNull);
    expect(tx!.baseAmount, isNull);
  });

  test('(update) 远端显式带 baseAmount 键 → 直接采用,不走反推', () async {
    final lid = await seedLedger();
    const txSyncId = 'tx-base-4';

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 2691,
      happenedAt: DateTime(2026, 9, 1),
      syncId: txSyncId,
    );

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: txSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': txSyncId,
        'type': 'expense',
        'amount': 2691,
        'happenedAt': '2026-09-01T00:00:00Z',
        'feeAmount': 40,
        'discountAmount': 0,
        'baseAmount': 2600, // 故意跟反推结果(2651)不同,验证优先采用 payload 值
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(txSyncId);
    expect(tx, isNotNull);
    expect(tx!.baseAmount, 2600);
  });
}
