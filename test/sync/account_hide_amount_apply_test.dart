// 帳戶頁面單帳戶金額隱藏(account.hideAmount) 同步 apply 路径的 D6「缺键
// 保留」语义测试,跟 test/sync/account_hidden_apply_test.dart 同款范式——两者
// 都是負極性、預設 false,insert 缺键时默认值也是 false。

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

  test('(D6) 远端 upsert 省略 hideAmount 键 → 本地 true 仍保留', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-hideamt-1';

    final aid = await repo.createAccount(
      ledgerId: lid,
      name: 'A',
      syncId: accountSyncId,
    );
    await repo.updateAccount(aid, hideAmount: true);

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: accountSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': accountSyncId,
        'name': 'A-renamed',
        'type': 'cash',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        // 注意:故意省略 hideAmount
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.name, 'A-renamed', reason: 'name 应被远端更新');
    expect(a.hideAmount, true, reason: '缺键不应清空本地已有的 hideAmount(D6)');
  });

  test('(D6) 远端 upsert 显式 hideAmount=true → 覆盖本地 false', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-hideamt-2';

    await repo.createAccount(
      ledgerId: lid,
      name: 'A',
      syncId: accountSyncId,
    );

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: accountSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': accountSyncId,
        'name': 'A',
        'type': 'cash',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        'hideAmount': true,
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.hideAmount, true, reason: '显式 true 应覆盖本地 false');
  });

  test('(insert) 远端新增账户带 hideAmount=true → 本地插入保留', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-hideamt-3';

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: accountSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': accountSyncId,
        'name': 'B',
        'type': 'cash',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        'hideAmount': true,
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.hideAmount, true);
  });

  test('(insert) 远端新增账户缺 hideAmount 键 → 本地插入默认 false', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-hideamt-4';

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: accountSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': accountSyncId,
        'name': 'C',
        'type': 'cash',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        // 注意:故意省略 hideAmount
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.hideAmount, false,
        reason: '跟 hidden 同款負極性,hideAmount 缺键插入默认 false(金額不隱藏)');
  });
}
