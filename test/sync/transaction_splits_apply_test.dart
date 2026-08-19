// v38 拆帳(split transaction)同步测试:
// - pull:远端 splits 非空 → 本地 hasSplits=true、categoryId 清空、明細按
//   syncId 反查本地分类写入 TransactionSplits
// - pull:远端 splits=[] → 本地還原成單一分類(明細清空,categoryId 采用
//   payload 自带的值)
// - pull:payload 缺 splits 键(旧版 App)→ 不动本地已有拆帳明細/状态
// - push:本地拆帳交易序列化后 splits 数组带正确的 categoryId(分类 syncId)/
//   categoryName/amount/note,顶层 categoryName 为 null(拆帳交易没有单一分类)

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/data/repositories/transaction_repository.dart';

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

  Future<int> seedCategory(String name, String syncId) async {
    final id = await repo.createCategory(name: name, kind: 'expense');
    await (db.update(db.categories)..where((c) => c.id.equals(id)))
        .write(CategoriesCompanion(syncId: Value(syncId)));
    return id;
  }

  test('(insert) 远端新增拆帳交易 → 本地 hasSplits=true、categoryId=null、明細写入', () async {
    final lid = await seedLedger();
    final food = await seedCategory('餐饮', 'cat-food');
    final cloth = await seedCategory('衣物', 'cat-cloth');
    const syncId = 'tx-split-1';

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'expense',
        'amount': 100,
        'happenedAt': '2026-08-01T00:00:00Z',
        'categoryName': null,
        'accountName': '',
        'accountId': '',
        'toAccountName': '',
        'toAccountId': '',
        'splits': [
          {'categoryId': 'cat-food', 'categoryName': '餐饮', 'amount': 60, 'note': '午饭'},
          {'categoryId': 'cat-cloth', 'categoryName': '衣物', 'amount': 40},
        ],
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx, isNotNull);
    expect(tx!.hasSplits, isTrue);
    expect(tx.categoryId, isNull);

    final splits = await repo.getTransactionSplits(tx.id);
    expect(splits.length, 2);
    expect(splits[0].categoryId, food);
    expect(splits[0].amount, 60);
    expect(splits[0].note, '午饭');
    expect(splits[1].categoryId, cloth);
    expect(splits[1].amount, 40);
  });

  test('(update) 远端把 splits 清空 → 本地還原成單一分類,明細清空', () async {
    final lid = await seedLedger();
    final food = await seedCategory('餐饮', 'cat-food');
    final cloth = await seedCategory('衣物', 'cat-cloth');
    const syncId = 'tx-split-2';

    // 本地先建一笔拆帳交易
    final localId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 8, 1),
      syncId: syncId,
      splits: [
        TransactionSplitInput(categoryId: food, amount: 60),
        TransactionSplitInput(categoryId: cloth, amount: 40),
      ],
    );

    // 远端还原成单一分类(食物),splits 显式发 []
    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'expense',
        'amount': 100,
        'happenedAt': '2026-08-01T00:00:00Z',
        'categoryName': '餐饮',
        'categoryId': 'cat-food',
        'accountName': '',
        'accountId': '',
        'toAccountName': '',
        'toAccountId': '',
        'splits': [],
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx, isNotNull);
    expect(tx!.id, localId);
    expect(tx.hasSplits, isFalse);
    expect(tx.categoryId, food);
    expect(await repo.getTransactionSplits(localId), isEmpty);
  });

  test('远端 upsert 省略 splits 键 → 本地已有拆帳明細/状态保留', () async {
    final lid = await seedLedger();
    final food = await seedCategory('餐饮', 'cat-food');
    final cloth = await seedCategory('衣物', 'cat-cloth');
    const syncId = 'tx-split-3';

    final localId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 8, 1),
      syncId: syncId,
      splits: [
        TransactionSplitInput(categoryId: food, amount: 60),
        TransactionSplitInput(categoryId: cloth, amount: 40),
      ],
    );

    // 模拟旧版 App 的 partial update,只改 note,不带 splits 键
    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: syncId,
      ledgerId: '$lid',
      payload: {
        'syncId': syncId,
        'type': 'expense',
        'amount': 100,
        'happenedAt': '2026-08-01T00:00:00Z',
        'note': '旧客户端改的备注',
        'accountName': '',
        'accountId': '',
        'toAccountName': '',
        'toAccountId': '',
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId(syncId);
    expect(tx, isNotNull);
    expect(tx!.id, localId);
    expect(tx.note, '旧客户端改的备注');
    expect(tx.hasSplits, isTrue, reason: '缺 splits 键不应清空本地已有拆帳状态');
    expect((await repo.getTransactionSplits(localId)).length, 2);
  });
}
