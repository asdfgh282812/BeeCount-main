// 帳戶「不納入總餘額」(account.includeInTotal) 同步 apply 路径的 D6「缺键
// 保留」语义测试，跟 test/sync/account_hidden_apply_test.dart 同款范式。
//
// 跟 hidden 的关键差异：includeInTotal 是正极性、预设 true(=納入)，所以
// insert 缺键时的默认值是 true，不是 false——这是本文件要钉住的回归点。

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

  test('(D6) 远端 upsert 省略 includeInTotal 键 → 本地 false 仍保留', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-incl-1';

    final aid = await repo.createAccount(
      ledgerId: lid,
      name: 'A',
      syncId: accountSyncId,
    );
    await repo.updateAccount(aid, includeInTotal: false);

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
        // 注意:故意省略 includeInTotal
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.name, 'A-renamed', reason: 'name 应被远端更新');
    expect(a.includeInTotal, false, reason: '缺键不应清空本地已有的 includeInTotal(D6)');
  });

  test('(D6) 远端 upsert 显式 includeInTotal=false → 覆盖本地 true', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-incl-2';

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
        'includeInTotal': false,
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.includeInTotal, false, reason: '显式 false 应覆盖本地 true');
  });

  test('(insert) 远端新增账户带 includeInTotal=false → 本地插入保留', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-incl-3';

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
        'includeInTotal': false,
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.includeInTotal, false);
  });

  test('(insert) 远端新增账户缺 includeInTotal 键 → 本地插入默认 true', () async {
    final lid = await seedLedger();
    const accountSyncId = 'ax-incl-4';

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
        // 注意:故意省略 includeInTotal
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(accountSyncId)))
        .getSingle();
    expect(a.includeInTotal, true,
        reason: '跟 hidden(默认 false)不同,includeInTotal 缺键插入默认 true(=納入)');
  });
}
