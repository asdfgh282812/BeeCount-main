// 專案(v44 project,取代分類預算)Repository 層測試:CRUD、軟/硬刪除規則
// (有交易關聯→封存,沒有→硬刪)、projectHasTransactions。

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

  Future<int> seedLedger() {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(name: '测试账本'));
  }

  test('建立專案 → 預設 enabled=true、有 syncId', () async {
    final lid = await seedLedger();
    final id = await repo.createProject(
      ledgerId: lid,
      name: '旅遊基金',
      budgetAmount: 5000,
    );

    final project = await repo.getProject(id);
    expect(project, isNotNull);
    expect(project!.name, '旅遊基金');
    expect(project.budgetAmount, 5000);
    expect(project.enabled, isTrue);
    expect(project.periodType, 'monthly');
    expect(project.syncId, isNotNull);
    expect(project.syncId, isNotEmpty);
  });

  test('budgetAmount 留空 → 純記錄型專案', () async {
    final lid = await seedLedger();
    final id = await repo.createProject(ledgerId: lid, name: '純記錄');

    final project = await repo.getProject(id);
    expect(project!.budgetAmount, isNull);
  });

  test('updateProject clearBudgetAmount → 改成純記錄型', () async {
    final lid = await seedLedger();
    final id = await repo.createProject(
        ledgerId: lid, name: '專案 A', budgetAmount: 1000);

    await repo.updateProject(id, clearBudgetAmount: true);

    final project = await repo.getProject(id);
    expect(project!.budgetAmount, isNull);
  });

  test('無交易關聯的專案 → deleteProject 直接硬刪除', () async {
    final lid = await seedLedger();
    final id = await repo.createProject(ledgerId: lid, name: '待刪專案');

    await repo.deleteProject(id);

    expect(await repo.getProject(id), isNull);
  });

  test('有交易關聯的專案 → deleteProject 只封存(enabled=false),不刪除',
      () async {
    final lid = await seedLedger();
    final id = await repo.createProject(ledgerId: lid, name: '有交易的專案');
    final project = (await repo.getProject(id))!;

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 100,
      happenedAt: DateTime(2026, 1, 1),
      projectSyncId: project.syncId,
    );

    await repo.deleteProject(id);

    final after = await repo.getProject(id);
    expect(after, isNotNull, reason: '有交易關聯不應該被硬刪除');
    expect(after!.enabled, isFalse);
  });

  test('projectHasTransactions:命中/不命中', () async {
    final lid = await seedLedger();
    final id = await repo.createProject(ledgerId: lid, name: '專案 B');
    final project = (await repo.getProject(id))!;

    expect(await repo.projectHasTransactions(project.syncId!), isFalse);

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 50,
      happenedAt: DateTime(2026, 1, 1),
      projectSyncId: project.syncId,
    );

    expect(await repo.projectHasTransactions(project.syncId!), isTrue);
  });

  test('getAllProjects 預設不含已封存,includeDisabled=true 才看得到', () async {
    final lid = await seedLedger();
    final activeId = await repo.createProject(ledgerId: lid, name: '進行中');
    final archivedId = await repo.createProject(ledgerId: lid, name: '已封存');
    await repo.updateProject(archivedId, enabled: false);

    final visible = await repo.getAllProjects(lid);
    expect(visible.map((p) => p.id), contains(activeId));
    expect(visible.map((p) => p.id), isNot(contains(archivedId)));

    final all = await repo.getAllProjects(lid, includeDisabled: true);
    expect(all.map((p) => p.id), containsAll([activeId, archivedId]));
  });

  test('sortOrder 決定 getAllProjects 排序', () async {
    final lid = await seedLedger();
    final second =
        await repo.createProject(ledgerId: lid, name: '第二', sortOrder: 2);
    final first =
        await repo.createProject(ledgerId: lid, name: '第一', sortOrder: 1);

    final all = await repo.getAllProjects(lid);
    expect(all.map((p) => p.id).toList(), [first, second]);
  });

  test('setTransactionProjectLink 可以事後改連結/清空', () async {
    final lid = await seedLedger();
    final projectId = await repo.createProject(ledgerId: lid, name: '專案 C');
    final project = (await repo.getProject(projectId))!;

    final txId = await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 20,
      happenedAt: DateTime(2026, 1, 1),
    );

    await repo.setTransactionProjectLink(
        id: txId, projectSyncId: project.syncId);
    var tx = await repo.getTransactionById(txId);
    expect(tx!.projectSyncId, project.syncId);

    await repo.setTransactionProjectLink(id: txId, projectSyncId: null);
    tx = await repo.getTransactionById(txId);
    expect(tx!.projectSyncId, isNull);
  });

  group('getProjectUsage', () {
    test('monthly:只加總落在本期(帳本 monthStartDay)內的支出交易', () async {
      final lid = await seedLedger();
      await repo.updateLedger(id: lid, monthStartDay: 10);
      final id = await repo.createProject(
          ledgerId: lid, name: '月度專案', budgetAmount: 1000);
      final project = (await repo.getProject(id))!;

      // now=2026-03-15 → 周期跟随 monthStartDay=10:[2026-03-10, 2026-04-10)。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 100,
        happenedAt: DateTime(2026, 3, 12),
        projectSyncId: project.syncId,
      );
      // 上一期(2/10~3/10)内,不该被算进本期。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 999,
        happenedAt: DateTime(2026, 3, 1),
        projectSyncId: project.syncId,
      );
      // 收入交易不算花费。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'income',
        amount: 500,
        happenedAt: DateTime(2026, 3, 12),
        projectSyncId: project.syncId,
      );

      final usage =
          await repo.getProjectUsage(project, DateTime(2026, 3, 15));
      expect(usage.used, 100);
      expect(usage.budget, 1000);
      expect(usage.remaining, 900);
      expect(usage.periodStart, DateTime(2026, 3, 10));
      expect(usage.periodEnd, DateTime(2026, 4, 10));
    });

    test('budgetAmount 為 null(純記錄) → remaining/rate 皆為 null', () async {
      final lid = await seedLedger();
      final id = await repo.createProject(ledgerId: lid, name: '純記錄專案');
      final project = (await repo.getProject(id))!;

      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 42,
        happenedAt: DateTime.now(),
        projectSyncId: project.syncId,
      );

      final usage = await repo.getProjectUsage(project, DateTime.now());
      expect(usage.used, 42);
      expect(usage.budget, isNull);
      expect(usage.remaining, isNull);
      expect(usage.rate, isNull);
    });

    test('yearly:以自然年計算', () async {
      final lid = await seedLedger();
      final id = await repo.createProject(
          ledgerId: lid,
          name: '年度專案',
          budgetAmount: 12000,
          periodType: 'yearly');
      final project = (await repo.getProject(id))!;

      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 300,
        happenedAt: DateTime(2026, 6, 1),
        projectSyncId: project.syncId,
      );
      // 去年的交易不算今年。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 999,
        happenedAt: DateTime(2025, 12, 31),
        projectSyncId: project.syncId,
      );

      final usage =
          await repo.getProjectUsage(project, DateTime(2026, 8, 27));
      expect(usage.used, 300);
      expect(usage.periodStart, DateTime(2026, 1, 1));
      expect(usage.periodEnd, DateTime(2027, 1, 1));
    });

    test('fixed:以 periodStart/periodEnd(含當天)計算,不受 now 影響周期範圍',
        () async {
      final lid = await seedLedger();
      final id = await repo.createProject(
        ledgerId: lid,
        name: '固定週期專案',
        budgetAmount: 5000,
        periodType: 'fixed',
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 8, 31),
      );
      final project = (await repo.getProject(id))!;

      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 200,
        happenedAt: DateTime(2026, 8, 31, 23, 0),
        projectSyncId: project.syncId,
      );
      // 9/1 已超出區間。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 999,
        happenedAt: DateTime(2026, 9, 1),
        projectSyncId: project.syncId,
      );

      final usage =
          await repo.getProjectUsage(project, DateTime(2026, 8, 27));
      expect(usage.used, 200);
      expect(usage.periodStart, DateTime(2026, 8, 1));
      expect(usage.periodEnd, DateTime(2026, 9, 1));
    });

    test('carryoverEnabled:monthly 專案結轉上期結餘(可為負)', () async {
      final lid = await seedLedger();
      final id = await repo.createProject(
        ledgerId: lid,
        name: '結轉專案',
        budgetAmount: 1000,
        carryoverEnabled: true,
      );
      final project = (await repo.getProject(id))!;

      // 上一期(1月)花了 300,結餘 700 帶進本期(2月)。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 300,
        happenedAt: DateTime(2026, 1, 15),
        projectSyncId: project.syncId,
      );
      // 本期(2月)花了 100。
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 100,
        happenedAt: DateTime(2026, 2, 10),
        projectSyncId: project.syncId,
      );

      final usage =
          await repo.getProjectUsage(project, DateTime(2026, 2, 15));
      expect(usage.used, 100);
      expect(usage.carriedOver, 700);
      expect(usage.effectiveBudget, 1700);
      expect(usage.remaining, 1600);
    });

    test('carryoverEnabled 但 periodType=fixed → 不生效(無上一期概念)',
        () async {
      final lid = await seedLedger();
      final id = await repo.createProject(
        ledgerId: lid,
        name: '固定+結轉專案(應忽略)',
        budgetAmount: 1000,
        periodType: 'fixed',
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 8, 31),
        carryoverEnabled: true,
      );
      final project = (await repo.getProject(id))!;

      final usage =
          await repo.getProjectUsage(project, DateTime(2026, 8, 15));
      expect(usage.carriedOver, isNull);
      expect(usage.effectiveBudget, 1000);
    });
  });

  test('getAllProjectUsages 依 sortOrder 回傳所有專案的花費統計', () async {
    final lid = await seedLedger();
    final firstId = await repo.createProject(
        ledgerId: lid, name: '第一', budgetAmount: 100, sortOrder: 1);
    final secondId = await repo.createProject(
        ledgerId: lid, name: '第二', budgetAmount: 200, sortOrder: 2);
    final firstProject = (await repo.getProject(firstId))!;

    await repo.addTransaction(
      ledgerId: lid,
      type: 'expense',
      amount: 30,
      happenedAt: DateTime.now(),
      projectSyncId: firstProject.syncId,
    );

    final usages = await repo.getAllProjectUsages(lid, DateTime.now());
    expect(usages.map((u) => u.project.id).toList(), [firstId, secondId]);
    expect(usages.first.usage.used, 30);
    expect(usages.last.usage.used, 0);
  });
}
