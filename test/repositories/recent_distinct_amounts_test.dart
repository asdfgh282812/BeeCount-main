/// 新增交易页「常用金額」列的資料來源:`getRecentDistinctAmounts`。
///
/// 覆蓋:
/// - 依 ledgerId + categoryId 過濾,不同分類/不同帳本的交易不會混進來。
/// - 同一金額出現多次只回傳一筆(distinct)。
/// - 依最後使用時間(happenedAt)倒序,而非依交易 id 或金額大小排序。
/// - limit 生效。
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  test('依 ledgerId+categoryId 過濾、distinct、依最後使用時間倒序', () async {
    final lid = await repo.createLedger(name: 'L');
    final otherLid = await repo.createLedger(name: 'L2');
    final catA = await repo.createCategory(name: '餐饮', kind: 'expense');
    final catB = await repo.createCategory(name: '交通', kind: 'expense');

    // catA:39 用了兩次(最後一次比較晚)、380 用一次(最早)、101 用一次(最晚)。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 380,
      categoryId: catA,
      happenedAt: DateTime(2026, 1, 1),
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 39,
      categoryId: catA,
      happenedAt: DateTime(2026, 1, 2),
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 39,
      categoryId: catA,
      happenedAt: DateTime(2026, 1, 3),
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 101,
      categoryId: catA,
      happenedAt: DateTime(2026, 1, 4),
    );
    // 不同分類,不應混進 catA 的結果。
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 999,
      categoryId: catB,
      happenedAt: DateTime(2026, 1, 5),
    );
    // 不同帳本,即使同分類 id 也不該混進來。
    await repo.addTransaction(
      ledgerId: otherLid,
      type: 'expense',
      amount: 888,
      categoryId: catA,
      happenedAt: DateTime(2026, 1, 6),
    );

    final amounts = await repo.getRecentDistinctAmounts(
      ledgerId: lid,
      categoryId: catA,
    );

    expect(amounts, [101, 39, 380]);
  });

  test('limit 生效', () async {
    final lid = await repo.createLedger(name: 'L');
    final cat = await repo.createCategory(name: '餐饮', kind: 'expense');
    for (var i = 0; i < 5; i++) {
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: (i + 1).toDouble(),
        categoryId: cat,
        happenedAt: DateTime(2026, 1, 1 + i),
      );
    }

    final amounts = await repo.getRecentDistinctAmounts(
      ledgerId: lid,
      categoryId: cat,
      limit: 2,
    );

    expect(amounts, [5, 4]);
  });
}
