// 專案分類子預算(v56 project_category_budget,Cloud 端尚未實作)同步 apply
// 路径测试。ledger-scope 新 entity type,全量恆發(不做 partial merge,同
// serializeProjectCategoryBudget 注释)。projectSyncId/categorySyncId 都要
// 解析成本地 int id,任一解析不到就跳过不建孤儿行(同 _applyDebtChange 对
// ledger 的处理模式)。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' show Value;

import 'package:beecount/cloud/sync/change_tracker.dart';
import 'package:beecount/cloud/sync/sync_engine.dart';
import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';

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

  Future<int> seedLedger({String? syncId}) {
    return db.into(db.ledgers).insert(LedgersCompanion.insert(
          name: '测试账本',
          monthStartDay: const Value(1),
          syncId: Value(syncId),
        ));
  }

  Future<(int projectId, int categoryId)> seedProjectAndCategory(
      int ledgerId) async {
    final projectId =
        await repo.createProject(ledgerId: ledgerId, name: '旅遊基金');
    final categoryId = await db.into(db.categories).insert(
          CategoriesCompanion.insert(
            name: '餐飲',
            kind: 'expense',
            syncId: const Value('cat-1'),
          ),
        );
    return (projectId, categoryId);
  }

  test('(insert) 远端新增分类子预算 → 本地插入且 project/category 解析成 int id', () async {
    final lid = await seedLedger(syncId: 'ledger-1');
    final (projectId, _) = await seedProjectAndCategory(lid);
    final project = (await repo.getProject(projectId))!;

    provider.pushFakeChange(
      entityType: 'project_category_budget',
      entitySyncId: 'pcb-1',
      ledgerId: 'ledger-1',
      payload: {
        'syncId': 'pcb-1',
        'projectSyncId': project.syncId,
        'categorySyncId': 'cat-1',
        'mode': 'fixed',
        'fixedAmount': 1200.0,
        'percentage': null,
        'carryoverEnabled': false,
      },
    );

    await engine.pull('');

    final rows = await repo.getProjectCategoryBudgets(projectId);
    expect(rows, hasLength(1));
    expect(rows.first.syncId, 'pcb-1');
    expect(rows.first.mode, 'fixed');
    expect(rows.first.fixedAmount, 1200.0);
  });

  test('远端 upsert 覆盖既有分类子预算(mode 从 fixed 改 percentage)', () async {
    final lid = await seedLedger(syncId: 'ledger-2');
    final (projectId, categoryId) = await seedProjectAndCategory(lid);
    final project = (await repo.getProject(projectId))!;
    await repo.upsertProjectCategoryBudget(
      projectId: projectId,
      categoryId: categoryId,
      mode: 'fixed',
      fixedAmount: 500,
    );
    final existing = (await repo.getProjectCategoryBudgets(projectId)).single;

    provider.pushFakeChange(
      entityType: 'project_category_budget',
      entitySyncId: existing.syncId!,
      ledgerId: 'ledger-2',
      payload: {
        'syncId': existing.syncId,
        'projectSyncId': project.syncId,
        'categorySyncId': 'cat-1',
        'mode': 'percentage',
        'fixedAmount': null,
        'percentage': 30.0,
        'carryoverEnabled': false,
      },
    );

    await engine.pull('');

    final after = (await repo.getProjectCategoryBudgets(projectId)).single;
    expect(after.mode, 'percentage');
    expect(after.percentage, 30.0);
    expect(after.fixedAmount, isNull);
  });

  test('(delete) 远端刪除分类子预算 → 本地整列刪除', () async {
    final lid = await seedLedger(syncId: 'ledger-3');
    final (projectId, categoryId) = await seedProjectAndCategory(lid);
    await repo.upsertProjectCategoryBudget(
      projectId: projectId,
      categoryId: categoryId,
      mode: 'fixed',
      fixedAmount: 500,
    );
    final existing = (await repo.getProjectCategoryBudgets(projectId)).single;

    provider.pushFakeChange(
      entityType: 'project_category_budget',
      entitySyncId: existing.syncId!,
      ledgerId: 'ledger-3',
      action: 'delete',
    );

    await engine.pull('');

    expect(await repo.getProjectCategoryBudgets(projectId), isEmpty);
  });

  test('project/category 本地都未就绪 → 跳过不建孤儿行', () async {
    final lid = await seedLedger(syncId: 'ledger-4');

    provider.pushFakeChange(
      entityType: 'project_category_budget',
      entitySyncId: 'pcb-orphan',
      ledgerId: 'ledger-4',
      payload: {
        'syncId': 'pcb-orphan',
        'projectSyncId': 'project-not-synced-yet',
        'categorySyncId': 'category-not-synced-yet',
        'mode': 'fixed',
        'fixedAmount': 100.0,
        'carryoverEnabled': false,
      },
    );

    await engine.pull('');

    final rows = await (db.select(db.projectCategoryBudgets)).get();
    expect(rows, isEmpty);
  });
}
