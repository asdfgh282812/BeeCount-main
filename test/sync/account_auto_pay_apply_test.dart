// 信用卡到期自動扣繳(autoPayEnabled / autoPayFromAccountId)同步 apply
// 路径的语义测试,見 docs/changes/2026-09-07-credit-card-auto-pay-fields.md。
//
// 跟 account_swipesmart_apply_test.dart / account_parent_apply_test.dart
// 同款范式:
//   - autoPayEnabled 是 D6 缺鍵保留语义(payload 省略键 → 本地已有值不能被
//     静默清空;insert 缺鍵落預設 false),跟 hidden/includeInTotal 同款。
//   - autoPayFromAccountId 是 containsKey 保護 + 空字符串清空語義(唯一能
//     清空的路径),跟 parentAccountId/swipesmartCardId 同款。
//
// 用 engine.pull('') 走真实 applyRemoteChange seam。

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

  test('远端 upsert 省略 autoPayEnabled/autoPayFromAccountId 键 → 本地已有设定仍保留',
      () async {
    final lid = await seedLedger();
    const syncId = 'ap-acc-1';

    final accId = await repo.createAccount(
      ledgerId: lid,
      name: '大戶信用卡',
      type: 'credit_card',
      syncId: syncId,
    );
    await repo.updateAccount(accId,
        autoPayEnabled: true, autoPayFromAccountId: 'src-existing');

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
        // 故意省略 autoPayEnabled / autoPayFromAccountId
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)..where((t) => t.id.equals(accId)))
        .getSingle();
    expect(a.name, '大戶信用卡-改名');
    expect(a.autoPayEnabled, isTrue, reason: '缺键不应清空本地已开启的自動扣繳');
    expect(a.autoPayFromAccountId, 'src-existing', reason: '缺键不应清空本地已有的來源帳戶');
  });

  test('远端 upsert 显式 autoPayEnabled=false + 空字符串来源 → 清空本地设定', () async {
    final lid = await seedLedger();
    const syncId = 'ap-acc-2';

    final accId = await repo.createAccount(
      ledgerId: lid,
      name: '大戶信用卡',
      type: 'credit_card',
      syncId: syncId,
    );
    await repo.updateAccount(accId,
        autoPayEnabled: true, autoPayFromAccountId: 'src-existing');

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
        'autoPayEnabled': false,
        'autoPayFromAccountId': '',
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)..where((t) => t.id.equals(accId)))
        .getSingle();
    expect(a.autoPayEnabled, isFalse);
    expect(a.autoPayFromAccountId, isNull, reason: '空字符串应清空來源帳戶');
  });

  test('远端新增账户带 autoPayEnabled=true + autoPayFromAccountId → 插入分支帶入該兩欄位',
      () async {
    final lid = await seedLedger();
    const syncId = 'ap-acc-3';

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
        'autoPayEnabled': true,
        'autoPayFromAccountId': 'src-999',
      },
    );

    await engine.pull('');

    final a = await (db.select(db.accounts)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingle();
    expect(a.autoPayEnabled, isTrue);
    expect(a.autoPayFromAccountId, 'src-999');
  });
}
