// v44 專案功能上線的一次性遷移測試:分類預算 → 專案 + 歷史交易回填 +
// 冪等性(旗標成功後不重跑;失敗不設旗標、下次重試)。

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/services/data/project_migration_service.dart';

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

  Future<int> seedLedger() =>
      db.into(db.ledgers).insert(LedgersCompanion.insert(name: '测试账本'));

  Future<int> seedExpenseCategory(String name) => db
      .into(db.categories)
      .insert(CategoriesCompanion.insert(name: name, kind: 'expense'));

  test('分類預算轉成專案,且全部歷史交易被回填 projectSyncId', () async {
    final lid = await seedLedger();
    final catId = await seedExpenseCategory('餐飲');

    await repo.createBudget(
      ledgerId: lid,
      type: 'category',
      categoryId: catId,
      amount: 3000,
    );

    // 三筆舊的餐飲支出交易(遷移前建立,模擬「全部歷史」)。
    for (var i = 0; i < 3; i++) {
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 100.0 + i,
        categoryId: catId,
        happenedAt: DateTime(2025, 1, 1 + i),
      );
    }
    // 一筆不同分類的交易,不該被回填。
    final otherCatId = await seedExpenseCategory('交通');
    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 50,
      categoryId: otherCatId,
      happenedAt: DateTime(2025, 1, 10),
    );

    final prefs = await SharedPreferences.getInstance();
    await ProjectMigrationService(repo).runIfNeeded(prefsOverride: prefs);

    // 分類預算已刪除。
    expect(await repo.getBudgetByCategory(lid, catId), isNull);

    // 轉出一個名稱=分類名、金額=原上限的專案。
    final projects = await repo.getAllProjects(lid, includeDisabled: true);
    expect(projects, hasLength(1));
    final project = projects.single;
    expect(project.name, '餐飲');
    expect(project.budgetAmount, 3000);
    expect(project.visibleOnHome, isFalse);

    // 三筆餐飲交易都被回填,交通那筆不受影響。
    final txs = await db.select(db.transactions).get();
    final foodTxs = txs.where((t) => t.categoryId == catId).toList();
    expect(foodTxs, hasLength(3));
    expect(foodTxs.every((t) => t.projectSyncId == project.syncId), isTrue);
    final otherTx = txs.firstWhere((t) => t.categoryId == otherCatId);
    expect(otherTx.projectSyncId, isNull);
  });

  test('總預算(type=total)不受影響,不轉成專案', () async {
    final lid = await seedLedger();
    await repo.createBudget(ledgerId: lid, type: 'total', amount: 10000);

    final prefs = await SharedPreferences.getInstance();
    await ProjectMigrationService(repo).runIfNeeded(prefsOverride: prefs);

    expect(await repo.getTotalBudget(lid), isNotNull);
    expect(await repo.getAllProjects(lid, includeDisabled: true), isEmpty);
  });

  test('冪等:旗標已設時 runIfNeeded 不重跑', () async {
    final lid = await seedLedger();
    final catId = await seedExpenseCategory('娛樂');
    await repo.createBudget(
        ledgerId: lid, type: 'category', categoryId: catId, amount: 500);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kProjectMigrationFlagKey, true);

    await ProjectMigrationService(repo).runIfNeeded(prefsOverride: prefs);

    // 旗標已是 true,不該執行任何轉換——分類預算原封不動,沒有專案。
    expect(await repo.getBudgetByCategory(lid, catId), isNotNull);
    expect(await repo.getAllProjects(lid, includeDisabled: true), isEmpty);
  });

  test('已封存(enabled=false)的分類預算 → 轉出的專案也是 enabled=false',
      () async {
    final lid = await seedLedger();
    final catId = await seedExpenseCategory('訂閱');
    final budgetId = await repo.createBudget(
        ledgerId: lid, type: 'category', categoryId: catId, amount: 200);
    await repo.updateBudget(budgetId, enabled: false);

    final prefs = await SharedPreferences.getInstance();
    await ProjectMigrationService(repo).runIfNeeded(prefsOverride: prefs);

    final projects = await repo.getAllProjects(lid, includeDisabled: true);
    expect(projects.single.enabled, isFalse);
  });
}
