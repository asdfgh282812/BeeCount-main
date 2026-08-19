// v38 拆帳(split transaction)展开进分类统计/预算用量的回归测试:
// - totalsByCategory / totalsByCategoryWithHierarchy 遇到 hasSplits=true
//   的交易时,改用各筆拆帳明細自己的分类累加,而不是掉进「未分类」桶
// - 拆帳明細金额按父交易的折算比例(nativeAmount/amount)缩放,跟未拆帳
//   交易同一套「统计一律用 nativeAmount」口径一致
// - 分类预算用量(getBudgetUsage 分类分支)同样把拆帳明細算进去

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/data/repositories/transaction_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
  });

  tearDown(() async => db.close());

  test('totalsByCategory:拆帳交易按明細分类拆开累加,不落入未分类', () async {
    final food = await repo.createCategory(name: '餐饮', kind: 'expense');
    final cloth = await repo.createCategory(name: '衣物', kind: 'expense');

    await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 7, 10),
      splits: [
        TransactionSplitInput(categoryId: food, amount: 60),
        TransactionSplitInput(categoryId: cloth, amount: 40),
      ],
    );
    // 一笔普通(未拆帳)交易也在同一个分类下,验证两者正确合并。
    await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 20,
      categoryId: food,
      happenedAt: DateTime(2026, 7, 11),
    );

    final rows = await repo.totalsByCategory(
      ledgerId: 1,
      type: 'expense',
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 8, 1),
    );

    final byId = {for (final r in rows) r.id: r.total};
    expect(byId[food], closeTo(80, 1e-9)); // 60(拆帳) + 20(普通)
    expect(byId[cloth], closeTo(40, 1e-9));
    expect(byId.containsKey(null), isFalse, reason: '不应该有交易落进「未分类」桶');
  });

  test('totalsByCategoryWithHierarchy:拆帳明細同样展开,保留分类层级信息', () async {
    final parent = await repo.createCategory(name: '生活', kind: 'expense');
    final child = await repo.createCategory(
        name: '餐饮', kind: 'expense', parentId: parent, level: 2);
    final other = await repo.createCategory(name: '娱乐', kind: 'expense');

    await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 50,
      happenedAt: DateTime(2026, 7, 10),
      splits: [
        TransactionSplitInput(categoryId: child, amount: 30),
        TransactionSplitInput(categoryId: other, amount: 20),
      ],
    );

    final rows = await repo.totalsByCategoryWithHierarchy(
      ledgerId: 1,
      type: 'expense',
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 8, 1),
    );

    final childRow = rows.firstWhere((r) => r.id == child);
    expect(childRow.total, closeTo(30, 1e-9));
    expect(childRow.parentId, parent);
    expect(childRow.level, 2);
    final otherRow = rows.firstWhere((r) => r.id == other);
    expect(otherRow.total, closeTo(20, 1e-9));
  });

  test('totalsByCategory:拆帳交易的多币种折算比例正确缩放明細金额', () async {
    final food = await repo.createCategory(name: '餐饮', kind: 'expense');
    final cloth = await repo.createCategory(name: '衣物', kind: 'expense');
    await db.customStatement(
        "INSERT INTO accounts (id, ledger_id, name, currency) "
        "VALUES (10, 1, 'Chase', 'USD')");

    // $100 拆成 60/40,折算比例 7.2(=720/100)。
    await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      accountId: 10,
      currencyCode: 'USD',
      nativeAmount: 720,
      happenedAt: DateTime(2026, 7, 10),
      splits: [
        TransactionSplitInput(categoryId: food, amount: 60),
        TransactionSplitInput(categoryId: cloth, amount: 40),
      ],
    );

    final rows = await repo.totalsByCategory(
      ledgerId: 1,
      type: 'expense',
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 8, 1),
    );
    final byId = {for (final r in rows) r.id: r.total};
    expect(byId[food], closeTo(432, 1e-6)); // 60 * 7.2
    expect(byId[cloth], closeTo(288, 1e-6)); // 40 * 7.2
  });

  test('getBudgetUsage(分类预算):拆帳交易的对应明細计入用量', () async {
    final food = await repo.createCategory(name: '餐饮', kind: 'expense');
    final cloth = await repo.createCategory(name: '衣物', kind: 'expense');

    final budgetId = await repo.createBudget(
      ledgerId: 1,
      type: 'category',
      categoryId: food,
      amount: 500,
    );

    await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 7, 10),
      splits: [
        TransactionSplitInput(categoryId: food, amount: 60),
        TransactionSplitInput(categoryId: cloth, amount: 40),
      ],
    );
    await repo.addTransaction(
      ledgerId: 1,
      type: 'expense',
      amount: 20,
      categoryId: food,
      happenedAt: DateTime(2026, 7, 11),
    );

    final usage = await repo.getBudgetUsage(budgetId, DateTime(2026, 7, 15));
    expect(usage.used, closeTo(80, 1e-9)); // 60(拆帳明細) + 20(普通交易)
  });
}
