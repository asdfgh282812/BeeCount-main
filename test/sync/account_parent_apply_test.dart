// 主帳戶(合併帳單分組,parentAccountId)同步 apply 路径的缺键保留语义测试。
//
// 跟 account_hidden_apply_test.dart 同款范式(D6):
//   - payload 省略 parentAccountId 键 → 本地已有的挂靠关系不能被静默清空
//     (老版本 App / 历史 sync_change 没有这个字段)
//   - payload 显式带空字符串 → 清空挂靠关系(唯一能清空的路径,
//     entity_serializer.dart 的约定见 serializeAccount 注释)
//   - payload 带非空 syncId → 更新挂靠关系
//
// 用 engine.pull('') 走真实 applyRemoteChange seam,跟
// test/sync/account_hidden_apply_test.dart 同款范式。

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

  test('远端 upsert 省略 parentAccountId 键 → 本地已有挂靠关系仍保留', () async {
    final lid = await seedLedger();
    const parentSyncId = 'ax-parent-1';
    const childSyncId = 'ax-child-1';

    await repo.createAccount(ledgerId: lid, name: '主卡', syncId: parentSyncId);
    final childId = await repo.createAccount(
      ledgerId: lid,
      name: '子卡',
      syncId: childSyncId,
      parentAccountId: parentSyncId,
    );

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: childSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': childSyncId,
        'name': '子卡-改名',
        'type': 'cash',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        // 故意省略 parentAccountId
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)..where((t) => t.id.equals(childId)))
        .getSingle();
    expect(a.name, '子卡-改名');
    expect(a.parentAccountId, parentSyncId, reason: '缺键不应清空本地已有的挂靠关系');
  });

  test('远端 upsert 显式空字符串 parentAccountId → 清空本地挂靠关系', () async {
    final lid = await seedLedger();
    const parentSyncId = 'ax-parent-2';
    const childSyncId = 'ax-child-2';

    await repo.createAccount(ledgerId: lid, name: '主卡', syncId: parentSyncId);
    final childId = await repo.createAccount(
      ledgerId: lid,
      name: '子卡',
      syncId: childSyncId,
      parentAccountId: parentSyncId,
    );

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: childSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': childSyncId,
        'name': '子卡',
        'type': 'cash',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        'parentAccountId': '',
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)..where((t) => t.id.equals(childId)))
        .getSingle();
    expect(a.parentAccountId, isNull, reason: '空字符串应清空挂靠关系');
  });

  test('远端新增账户带 parentAccountId → 本地插入保留挂靠关系', () async {
    final lid = await seedLedger();
    const parentSyncId = 'ax-parent-3';
    const childSyncId = 'ax-child-3';

    provider.pushFakeChange(
      entityType: 'account',
      entitySyncId: childSyncId,
      ledgerId: '$lid',
      payload: {
        'syncId': childSyncId,
        'name': '子卡',
        'type': 'cash',
        'currency': 'CNY',
        'initialBalance': 0.0,
        'sortOrder': 0,
        'parentAccountId': parentSyncId,
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(childSyncId)))
        .getSingle();
    expect(a.parentAccountId, parentSyncId);
  });
}
