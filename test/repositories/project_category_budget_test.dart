// 專案分類子預算(v56)+ 收入併入預算 repository 層測試:
// - getProjectCategoryBreakdown 的分組正確性(依 category_id GROUP BY,
//   expense/income 分開加總,筆數)
// - upsertProjectCategoryBudget 的 fixed/percentage 兩種模式(含更新既有列)
// - getProjectUsage 的 incomeIncludedInBudget 分支

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

void main() {
  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
  });

  tearDown(() async => db.close());

  Future<int> seedLedger() {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '测试账本',
          monthStartDay: const Value(1),
        ));
  }

  Future<int> seedCategory(String name, {String kind = 'expense'}) {
    return db.into(db.categories).insert(
          CategoriesCompanion.insert(name: name, kind: kind),
        );
  }

  test('getProjectCategoryBreakdown 依 category_id 分组,expense/income 分开加总',
      () async {
    final lid = await seedLedger();
    final foodId = await seedCategory('餐飲');
    final transportId = await seedCategory('交通');
    final projectId = await repo.createProject(ledgerId: lid, name: '旅遊');
    final project = (await repo.getProject(projectId))!;
    final syncId = project.syncId!;

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      categoryId: foodId,
      happenedAt: DateTime(2026, 6, 10),
      projectSyncId: syncId,
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 50,
      categoryId: foodId,
      happenedAt: DateTime(2026, 6, 12),
      projectSyncId: syncId,
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 200,
      categoryId: transportId,
      happenedAt: DateTime(2026, 6, 15),
      projectSyncId: syncId,
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 300,
      categoryId: transportId,
      happenedAt: DateTime(2026, 6, 15),
      projectSyncId: syncId,
    );
    // 不同期间(不应计入下面的查询范围)
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 999,
      categoryId: foodId,
      happenedAt: DateTime(2026, 7, 1),
      projectSyncId: syncId,
    );

    final breakdown = await repo.getProjectCategoryBreakdown(
      syncId,
      start: DateTime(2026, 6, 1),
      end: DateTime(2026, 7, 1),
    );

    final byCategory = {for (final b in breakdown) b.categoryId: b};
    expect(byCategory[foodId]!.expenseTotal, 150);
    expect(byCategory[foodId]!.incomeTotal, 0);
    expect(byCategory[foodId]!.recordCount, 2);
    expect(byCategory[transportId]!.expenseTotal, 200);
    expect(byCategory[transportId]!.incomeTotal, 300);
    expect(byCategory[transportId]!.recordCount, 2);
  });

  test('upsertProjectCategoryBudget: fixed/percentage 两种模式 + 更新既有列', () async {
    final lid = await seedLedger();
    final catId = await seedCategory('餐飲');
    final projectId =
        await repo.createProject(ledgerId: lid, name: '旅遊', budgetAmount: 1000);

    await repo.upsertProjectCategoryBudget(
      projectId: projectId,
      categoryId: catId,
      mode: 'fixed',
      fixedAmount: 300,
    );
    var rows = await repo.getProjectCategoryBudgets(projectId);
    expect(rows, hasLength(1));
    expect(rows.first.mode, 'fixed');
    expect(rows.first.fixedAmount, 300);

    // 同一 (projectId, categoryId) 再次呼叫应该是 update 而非新增一列
    await repo.upsertProjectCategoryBudget(
      projectId: projectId,
      categoryId: catId,
      mode: 'percentage',
      percentage: 25,
    );
    rows = await repo.getProjectCategoryBudgets(projectId);
    expect(rows, hasLength(1), reason: '同一分类再次 upsert 应更新既有列而非新增');
    expect(rows.first.mode, 'percentage');
    expect(rows.first.percentage, 25);
  });

  test('removeProjectCategoryBudget 直接刪列', () async {
    final lid = await seedLedger();
    final catId = await seedCategory('餐飲');
    final projectId = await repo.createProject(ledgerId: lid, name: '旅遊');

    await repo.upsertProjectCategoryBudget(
      projectId: projectId,
      categoryId: catId,
      mode: 'fixed',
      fixedAmount: 100,
    );
    expect(await repo.getProjectCategoryBudgets(projectId), hasLength(1));

    await repo.removeProjectCategoryBudget(projectId, catId);
    expect(await repo.getProjectCategoryBudgets(projectId), isEmpty);
  });

  test('getProjectUsage: incomeIncludedInBudget=true 时 effectiveBudget 併入收入',
      () async {
    final lid = await seedLedger();
    final projectId = await repo.createProject(
      ledgerId: lid,
      name: '旅遊',
      budgetAmount: 1000,
      incomeIncludedInBudget: true,
    );
    final project = (await repo.getProject(projectId))!;
    final syncId = project.syncId!;

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 200,
      happenedAt: DateTime(2026, 6, 10),
      projectSyncId: syncId,
    );
    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 150,
      happenedAt: DateTime(2026, 6, 12),
      projectSyncId: syncId,
    );

    final usage = await repo.getProjectUsage(project, DateTime(2026, 6, 20));
    expect(usage.used, 200);
    expect(usage.incomeIncluded, 150);
    expect(usage.effectiveBudget, 1150); // 1000(budget) + 150(income)
  });

  test('getProjectUsage: incomeIncludedInBudget=false 时不併入收入(既有行为)', () async {
    final lid = await seedLedger();
    final projectId = await repo.createProject(
      ledgerId: lid,
      name: '旅遊',
      budgetAmount: 1000,
    );
    final project = (await repo.getProject(projectId))!;
    final syncId = project.syncId!;

    await repo.addTransaction(
      ledgerId: lid,
      type: 'income',
      amount: 150,
      happenedAt: DateTime(2026, 6, 12),
      projectSyncId: syncId,
    );

    final usage = await repo.getProjectUsage(project, DateTime(2026, 6, 20));
    expect(usage.incomeIncluded, isNull);
    expect(usage.effectiveBudget, 1000);
  });
}
