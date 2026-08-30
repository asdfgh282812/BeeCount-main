// SwipeSmart 信用卡對照(swipesmartCardId)同步 apply 路径的缺键保留语义测试。
//
// 跟 account_parent_apply_test.dart 同款范式(D6):
//   - payload 省略 swipesmartCardId 键 → 本地已有的對照不能被静默清空
//     (老版本 App / 历史 sync_change 没有这个字段)
//   - payload 显式带空字符串 → 清空對照(唯一能清空的路径,
//     entity_serializer.dart 的约定见 serializeAccount 注释)
//   - payload 带非空 cardId → 新账户 insert 时带入對照
//
// 用 engine.pull('') 走真实 applyRemoteChange seam,跟
// test/sync/account_parent_apply_test.dart 同款范式。

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  test('远端 upsert 省略 swipesmartCardId 键 → 本地已有對照仍保留', () async {
    final lid = await seedLedger();
    const syncId = 'sw-acc-1';

    final accId = await repo.createAccount(
      ledgerId: lid,
      name: '大戶信用卡',
      type: 'credit_card',
      syncId: syncId,
    );
    await repo.updateAccount(accId, swipesmartCardId: 'sw-card-existing');

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'name': '大戶信用卡-改名',
        'type': 'credit_card',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        // 故意省略 swipesmartCardId
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)..where((t) => t.id.equals(accId)))
        .getSingle();
    expect(a.name, '大戶信用卡-改名');
    expect(a.swipesmartCardId, 'sw-card-existing', reason: '缺键不应清空本地已有的對照');
  });

  test('远端 upsert 显式空字符串 swipesmartCardId → 清空本地對照', () async {
    final lid = await seedLedger();
    const syncId = 'sw-acc-2';

    final accId = await repo.createAccount(
      ledgerId: lid,
      name: '大戶信用卡',
      type: 'credit_card',
      syncId: syncId,
    );
    await repo.updateAccount(accId, swipesmartCardId: 'sw-card-existing');

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'name': '大戶信用卡',
        'type': 'credit_card',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        'swipesmartCardId': '',
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)..where((t) => t.id.equals(accId)))
        .getSingle();
    expect(a.swipesmartCardId, isNull, reason: '空字符串应清空對照');
  });

  test('远端新增账户带 swipesmartCardId → 本地插入分支帶入該欄位', () async {
    final lid = await seedLedger();
    const syncId = 'sw-acc-3';

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'name': '大戶信用卡',
        'type': 'credit_card',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        'swipesmartCardId': 'sw-card-999',
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingle();
    expect(a.swipesmartCardId, 'sw-card-999');
  });
}
