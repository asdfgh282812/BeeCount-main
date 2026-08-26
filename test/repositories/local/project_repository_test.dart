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
}
