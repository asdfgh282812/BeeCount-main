// 账户 apply 的 partial-update 保留语义回归测试。
//
// 背景(2026-08-15 实测事故):web 端 PATCH /accounts/{id} 用
// `model_dump(exclude_unset=True)`(routers/write/accounts.py::update_acc），
// 只送用户实际改动的字段——广播给其它设备的 SyncChange.payload 就是这份
// partial dict，不是 server 自己 merge 出的全量快照（那份只写回 server 自己
// 的 projection，见 BeeCount-Cloud/src/sync_applier.py::_merge_from_spec）。
//
// `_applyAccountChange` 曾经对 type/currency 等字段用 `payload['x'] ?? 默认值`
// 无条件覆盖——当 web 只 PATCH parentAccountId（例如把一张信用卡挂进合并
// 帐单群组）时，广播出的 payload 不含 type/currency 键，旧代码就会把本地已
// 有的 type/currency 冲成 'cash'/'CNY'（实测：信用卡群组子卡被冲成现金 +
// 人民币）。本测试钉住修复：跟 hidden/parentAccountId 同款 containsKey 保护
// 现在也覆盖 type/currency/name/initialBalance/sortOrder/creditLimit/
// billingDay/paymentDueDay/bankName/cardLastFour/note。

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

  test('远端 upsert 只带 parentAccountId(缺 type/currency 键) → 本地 credit_card/USD 仍保留',
      () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-partial-1';

    // 本地先建一张信用卡账户(非 cash/CNY,便于跟错误默认值区分)
    final aid = await repo.createAccount(
      ledgerId: lid,
      name: '信用卡A',
      type: 'credit_card',
      currency: 'USD',
      syncId: accountSyncId,
    );
    expect((await (db.select(db.accounts)..where((a) => a.id.equals(aid))).getSingle()).type,
        'credit_card');

    // 模拟 web 端 PATCH 只改 parentAccountId(挂进合并帐单群组),
    // exclude_unset=True 广播出的 payload 不含 type/currency/name 等键。
    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: accountSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': accountSyncId,
        'parentAccountId': 'ax-group-1',
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.type, 'credit_card', reason: '缺键不应把 type 冲成默认值 cash');
    expect(a.currency, 'USD', reason: '缺键不应把 currency 冲成默认值 CNY');
    expect(a.name, '信用卡A', reason: '缺键不应把 name 清空');
    expect(a.parentAccountId, 'ax-group-1', reason: 'parentAccountId 应被更新');
  });

  test('远端 upsert 显式带 type/currency → 正常覆盖本地值', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-partial-2';

    await repo.createAccount(
      ledgerId: lid,
      name: '账户B',
      type: 'cash',
      currency: 'CNY',
      syncId: accountSyncId,
    );

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: accountSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': accountSyncId,
        'name': '账户B',
        'type': 'credit_card',
        'currency': 'USD',
        'initialBalance': 0.0,
        'sortOrder': 0,
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.type, 'credit_card', reason: '显式带键应正常覆盖');
    expect(a.currency, 'USD', reason: '显式带键应正常覆盖');
  });

  test('(insert) 远端新增账户缺 type/currency 键 → 落默认 cash/CNY', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-partial-3';

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: accountSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': accountSyncId,
        'name': '新账户',
        // 注意:故意省略 type/currency,模拟老数据/异常 payload
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.type, 'cash');
    expect(a.currency, 'CNY');
  });
}
