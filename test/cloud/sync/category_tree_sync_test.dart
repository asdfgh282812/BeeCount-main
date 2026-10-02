// 2026-09-29 事故回归:全新设备回放到一笔误删一级分类的 delete,旧版会连带
// 删掉本机子分类,交易全部变成「无分类」。
//
// (1) pull 删除一级分类 → 子分类保留(parentId 摘掉),交易引用不断。
// (2) 局部 upsert 没带 parentName/parentSyncId/level → 保留原父分类。
// (3) reconcileCategoriesFromServer:按 server parentName 接回父分类、补回
//     缺的分类、把指向不存在分类的交易按 server 交易的分类 syncId 接回。

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

import '_fakes/fake_beecount_cloud_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late FakeBeeCountCloudProvider provider;
  late SyncEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    final changeTracker = ChangeTracker(db);
    provider = FakeBeeCountCloudProvider();
    engine = SyncEngine(
      db: db,
      provider: provider,
      changeTracker: changeTracker,
      repo: LocalRepository(db, changeTracker: changeTracker),
    );
  });

  tearDown(() async => db.close());

  Map<String, dynamic> cat(String syncId, String name,
          {int level = 1, String? parentName}) =>
      {
        'syncId': syncId,
        'name': name,
        'kind': 'expense',
        'level': level,
        'sortOrder': 0,
        'icon': 'category',
        'iconType': 'material',
        if (parentName != null) 'parentName': parentName,
      };

  Future<Category> bySync(String syncId) =>
      (db.select(db.categories)..where((c) => c.syncId.equals(syncId)))
          .getSingle();

  test('(1) pull 删除一级分类不会连带删子分类', () async {
    provider.pushFakeChange(
        entityType: 'category', entitySyncId: 'p', payload: cat('p', '娛樂'));
    provider.pushFakeChange(
        entityType: 'category',
        entitySyncId: 'c',
        payload: cat('c', '遊戲', level: 2, parentName: '娛樂'));
    await engine.pull('');
    final child = await bySync('c');
    final ledgerId = await db
        .into(db.ledgers)
        .insert(LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
    final txId = await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 1563,
            categoryId: Value(child.id),
            syncId: const Value('tx1')));

    provider.pushFakeChange(
        entityType: 'category', entitySyncId: 'p', action: 'delete');
    await engine.pull('');

    final survived = await bySync('c');
    expect(survived.id, child.id, reason: '子分类本机 id 不能变,交易才接得上');
    expect(survived.parentId, isNull);
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(tx.categoryId, child.id);
  });

  test('(2) 局部 upsert 没带父分类键时保留原父分类', () async {
    provider.pushFakeChange(
        entityType: 'category', entitySyncId: 'p', payload: cat('p', '娛樂'));
    provider.pushFakeChange(
        entityType: 'category',
        entitySyncId: 'c',
        payload: cat('c', '遊戲', level: 2, parentName: '娛樂'));
    await engine.pull('');
    final parent = await bySync('p');

    provider.pushFakeChange(
        entityType: 'category',
        entitySyncId: 'c',
        payload: {
          'syncId': 'c',
          'name': '遊戲',
          'kind': 'expense',
          'color': '#009688'
        });
    await engine.pull('');

    final child = await bySync('c');
    expect(child.parentId, parent.id);
    expect(child.level, 2);
  });

  test('(3) reconcileCategoriesFromServer 修好断掉的分类树与交易', () async {
    final ledgerId = await db
        .into(db.ledgers)
        .insert(LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
    final parentId = await db.into(db.categories).insert(
        CategoriesCompanion.insert(
            name: '娛樂', kind: 'expense', syncId: const Value('p')));
    // 旧版级联删除后留下的样子:子分类没了父分类,交易指向已不存在的 id
    final childId = await db.into(db.categories).insert(
        CategoriesCompanion.insert(
            name: '遊戲',
            kind: 'expense',
            level: const Value(2),
            syncId: const Value('c')));
    final txId = await db.into(db.transactions).insert(
        TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'expense',
            amount: 1563,
            categoryId: const Value(9999),
            syncId: const Value('tx1')));

    provider.serverCategories.addAll(const [
      BeeCountCloudReadCategory(
          id: 'p', name: '娛樂', kind: 'expense', level: 1, lastChangeId: 1),
      BeeCountCloudReadCategory(
          id: 'c',
          name: '遊戲',
          kind: 'expense',
          level: 2,
          parentName: '娛樂',
          lastChangeId: 2),
      BeeCountCloudReadCategory(
          id: 'm',
          name: '電影',
          kind: 'expense',
          level: 2,
          parentName: '娛樂',
          lastChangeId: 3),
    ]);
    provider.serverTransactions.add(BeeCountCloudReadTransaction(
        id: 'tx1',
        txIndex: 0,
        txType: 'expense',
        amount: 1563,
        happenedAt: DateTime(2026, 9, 18),
        lastChangeId: 4,
        categoryId: 'c'));

    final r = await engine.reconcileCategoriesFromServer(ledgerId: ledgerId);

    expect((await bySync('c')).parentId, parentId);
    final movie = await bySync('m');
    expect(movie.parentId, parentId);
    expect(movie.level, 2);
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(tx.categoryId, childId);
    expect(r.transactions, 1);

    // 只改本机,不能产生任何待推送的 change
    final pending = await (db.select(db.localChanges)
          ..where((c) => c.pushedAt.isNull()))
        .get();
    expect(pending, isEmpty);
  });
}
