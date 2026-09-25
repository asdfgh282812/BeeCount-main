// 洞察页点击一级分类(饼图/排行)进入「分类汇总」时,一级分类一旦有子分类,
// 交易实际上记在子分类上——watchTransactionsByCategories 需要把父分类自身
// + 全部子分类的交易一起聚合返回,否则页面永远显示"暂无交易记录"。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('父分类自身查不到交易时,聚合子分类后能查到', () async {
    final lid = await repo.createLedger(name: 'L');
    final parent = await repo.createCategory(name: '個人', kind: 'expense');
    final child1 =
        await repo.createSubCategory(parentId: parent, name: '投資', kind: 'expense');
    final child2 =
        await repo.createSubCategory(parentId: parent, name: '稅金', kind: 'expense');

    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 100,
        categoryId: child1,
        happenedAt: DateTime(2026, 9, 1));
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 50,
        categoryId: child2,
        happenedAt: DateTime(2026, 9, 2));

    // 单独查父分类自身:空(符合"一级分类一旦有子分类,自身不再挂交易"的现状)。
    final ownOnly = await repo.watchTransactionsByCategory(parent).first;
    expect(ownOnly, isEmpty);

    // 聚合父分类 + 子分类:两笔都应出现,笔数/总额可正确计算。
    final aggregated =
        await repo.watchTransactionsByCategories([parent, child1, child2]).first;
    expect(aggregated.length, 2);
    expect(aggregated.fold(0.0, (s, t) => s + t.amount), 150);
  });

  test('按账本过滤仍然生效', () async {
    final lidA = await repo.createLedger(name: 'A');
    final lidB = await repo.createLedger(name: 'B');
    final parent = await repo.createCategory(name: '個人', kind: 'expense');
    final child =
        await repo.createSubCategory(parentId: parent, name: '投資', kind: 'expense');

    await repo.addTransaction(
        ledgerId: lidA,
        type: 'expense',
        amount: 100,
        categoryId: child,
        happenedAt: DateTime(2026, 9, 1));
    await repo.addTransaction(
        ledgerId: lidB,
        type: 'expense',
        amount: 999,
        categoryId: child,
        happenedAt: DateTime(2026, 9, 1));

    final aggregated = await repo
        .watchTransactionsByCategories([parent, child], ledgerId: lidA)
        .first;
    expect(aggregated.length, 1);
    expect(aggregated.first.amount, 100);
  });

  test('单个分类id时退化为原有单分类查询', () async {
    final lid = await repo.createLedger(name: 'L');
    final cat = await repo.createCategory(name: '餐饮', kind: 'expense');
    await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 20,
        categoryId: cat,
        happenedAt: DateTime(2026, 9, 1));

    final aggregated = await repo.watchTransactionsByCategories([cat]).first;
    expect(aggregated.length, 1);
    expect(aggregated.first.amount, 20);
  });
}
