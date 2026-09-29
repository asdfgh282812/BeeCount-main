// LocalRepository.getTransferCategory 合并多笔 transfer 分类时只在本机做,
// 不把 dupe 的 delete / 交易 update 推回云端。
//
// 背景(2026-09-29 实测):新设备全历史回放到一半时,本机会暂时出现多笔
// server 历史上真实存在过的 transfer 分类,UI 呼叫本方法就会记下 category
// delete 推回 server,把使用者云端合法存在的分类删掉。见
// docs/changes/2026-09-29-category-duplicate-pull-and-color-restore.md。

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late ChangeTracker changeTracker;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    changeTracker = ChangeTracker(db);
    repo = LocalRepository(db, changeTracker: changeTracker);
  });

  tearDown(() async => db.close());

  test('多笔 transfer 分类 → 本机合并到 id 最小,交易改挂,但不产生任何 local_changes',
      () async {
    final keeperId = await db.into(db.categories).insert(
        CategoriesCompanion.insert(
            name: '轉帳', kind: 'transfer', syncId: const Value('tr-A')));
    final dupeId = await db.into(db.categories).insert(
        CategoriesCompanion.insert(
            name: '轉帳', kind: 'transfer', syncId: const Value('tr-B')));
    final ledgerId = await db.into(db.ledgers).insert(
        LedgersCompanion.insert(name: 'L', syncId: const Value('L1')));
    final txId = await db.into(db.transactions).insert(
          TransactionsCompanion.insert(
            ledgerId: ledgerId,
            type: 'transfer',
            amount: 197,
            happenedAt: Value(DateTime.utc(2026, 9, 22)),
            categoryId: Value(dupeId),
            syncId: const Value('tx-1'),
          ),
        );
    final before = (await db.select(db.localChanges).get()).length;

    final keeper = await repo.getTransferCategory();

    expect(keeper.id, keeperId);
    final remaining = await (db.select(db.categories)
          ..where((c) => c.kind.equals('transfer')))
        .get();
    expect(remaining.map((c) => c.id), [keeperId]);
    final tx = await (db.select(db.transactions)
          ..where((t) => t.id.equals(txId)))
        .getSingle();
    expect(tx.categoryId, keeperId);

    final after = await db.select(db.localChanges).get();
    expect(after.length, before, reason: '背景去重不应推送任何变更到云端');
  });
}
