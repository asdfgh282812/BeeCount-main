// 專案(v44 project,取代分類預算)同步 apply 路径测试。
//
// project 是 ledger-scope 实体,跟 budget/debt 同款全量 UPSERT 语义(不是
// partial merge)——見 lib/cloud/sync/entity_serializer.dart::serializeProject
// 的注释。所有欄位恆發,这里也测缺鍵時的行為。
//
// 交易的 projectId(存 syncId)走既有 _applyTransactionChange 路径,这里也
// 顺带测 transaction payload 里的 projectId 键能正确落地成
// Transactions.projectSyncId。
//
// 用 engine.pull('') 走真实 applyRemoteChange seam(public 入口），
// FakeBeeCountCloudProvider.pushFakeChange 注入远端 change。

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

  test('(insert) 远端新增专案 → 本地插入且欄位齊全', () async {
    final lid = await seedLedger(syncId: 'ledger-1');

    provider.pushFakeChange(
      entityType: 'project',
      entitySyncId: 'project-1',
      ledgerId: 'ledger-1',
      payload: {
        'syncId': 'project-1',
        'ledgerSyncId': 'ledger-1',
        'name': '旅遊基金',
        'icon': '✈️',
        'budgetAmount': 8000.0,
        'periodType': 'fixed',
        'periodStart': '2026-07-01T00:00:00Z',
        'periodEnd': '2026-08-31T00:00:00Z',
        'carryoverEnabled': false,
        'visibleOnHome': true,
        'enabled': true,
        'sortOrder': 0,
      },
    );

    await engine.pull('');

    final project = await repo.getProjectBySyncId('project-1');
    expect(project, isNotNull);
    expect(project!.ledgerId, lid);
    expect(project.name, '旅遊基金');
    expect(project.icon, '✈️');
    expect(project.budgetAmount, 8000.0);
    expect(project.periodType, 'fixed');
    expect(project.periodStart, isNotNull);
    expect(project.periodEnd, isNotNull);
    expect(project.visibleOnHome, isTrue);
    expect(project.enabled, isTrue);
  });

  test('遠端 upsert 全量覆蓋 → budgetAmount/icon 缺鍵時視為清空(非 partial merge)',
      () async {
    final lid = await seedLedger(syncId: 'ledger-2');

    final id = await repo.createProject(
      ledgerId: lid,
      name: '舊名稱',
      icon: '🎯',
      budgetAmount: 1000,
    );
    final project = (await repo.getProject(id))!;

    provider.pushFakeChange(
      entityType: 'project',
      entitySyncId: project.syncId!,
      ledgerId: 'ledger-2',
      payload: {
        'syncId': project.syncId,
        'ledgerSyncId': 'ledger-2',
        'name': '新名稱',
        // icon / budgetAmount 缺鍵 → upsert 全量覆蓋語意下應視為清空
        'periodType': 'monthly',
        'carryoverEnabled': false,
        'visibleOnHome': true,
        'enabled': true,
        'sortOrder': 0,
      },
    );

    await engine.pull('');

    final after = await repo.getProjectBySyncId(project.syncId!);
    expect(after!.name, '新名稱');
    expect(after.icon, isNull);
    expect(after.budgetAmount, isNull);
  });

  test('(delete) 远端刪除专案 → 本地整列刪除', () async {
    final lid = await seedLedger(syncId: 'ledger-3');
    final id = await repo.createProject(ledgerId: lid, name: '待刪');
    final project = (await repo.getProject(id))!;

    provider.pushFakeChange(
      entityType: 'project',
      entitySyncId: project.syncId!,
      ledgerId: 'ledger-3',
      action: 'delete',
    );

    await engine.pull('');

    expect(await repo.getProjectBySyncId(project.syncId!), isNull);
  });

  test('交易 payload 的 projectId → 落地成 Transactions.projectSyncId',
      () async {
    final lid = await seedLedger(syncId: 'ledger-4');
    final projectId = await repo.createProject(ledgerId: lid, name: '餐飲');
    final project = (await repo.getProject(projectId))!;

    provider.pushFakeChange(
      entityType: 'transaction',
      entitySyncId: 'tx-1',
      ledgerId: 'ledger-4',
      payload: {
        'syncId': 'tx-1',
        'ledgerSyncId': 'ledger-4',
        'type': 'expense',
        'amount': 88.0,
        'happenedAt': '2026-08-01T12:00:00Z',
        'projectId': project.syncId,
      },
    );

    await engine.pull('');

    final tx = await repo.getTransactionBySyncId('tx-1');
    expect(tx, isNotNull);
    expect(tx!.projectSyncId, project.syncId);
  });
}
