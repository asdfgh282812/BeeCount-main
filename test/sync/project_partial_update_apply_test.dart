// 專案 v56 新增 4 欄位(incomeIncludedInBudget/dailyBudgetEnabled/
// dailyBudgetMode/reminderThresholdPercent)的 apply partial-update 保留
// 語意回歸測試。
//
// 背景:project 其它舊欄位(name/icon/budgetAmount 等)是全量覆蓋語意——缺鍵
// 視為清空(見 project_apply_test.dart)。但這 4 個新欄位刻意反過來,用
// containsKey 保護(比照 account.includeInTotal 的寫法):因為 Cloud 端目前
// 完全不認得這 4 個 key,任何一次由 Cloud 廣播回來的 project 變更payload
// 都不會帶這 4 個 key。如果沿用舊欄位「缺鍵=清空」的邏輯,本機剛設置好的
// 這些設定會被下一次 pull(哪怕只是改了 name 之類的舊欄位)打回預設值,
// 違反「本機優先寫入,多裝置間暫不同步」的過渡期設計(design doc
// 2026-09-06 §0 第 5 點)。本測試直接釘住這個保護有沒有生效。

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

  test('远端 upsert 只带舊欄位(缺 v56 新欄位鍵,模拟 Cloud 尚未实现)→ 本机 v56 设置仍保留', () async {
    final lid = await seedLedger(syncId: 'ledger-1');
    final id = await repo.createProject(
      ledgerId: lid,
      name: '旅遊基金',
      budgetAmount: 5000,
      incomeIncludedInBudget: true,
      dailyBudgetEnabled: true,
      dailyBudgetMode: 'fixed',
      reminderThresholdPercent: 80,
    );
    final project = (await repo.getProject(id))!;

    // 模拟 Cloud 端广播的 project 变更(只带它认得的旧欄位,不含 v56 新欄位)。
    provider.pushFakeChange(
      entityType: 'project',
      entitySyncId: project.syncId!,
      ledgerId: 'ledger-1',
      payload: {
        'syncId': project.syncId,
        'ledgerSyncId': 'ledger-1',
        'name': '旅遊基金(改名)',
        'budgetAmount': 5000.0,
        'periodType': 'monthly',
        'carryoverEnabled': false,
        'visibleOnHome': true,
        'enabled': true,
        'sortOrder': 0,
        // 故意不带 incomeIncludedInBudget/dailyBudgetEnabled/
        // dailyBudgetMode/reminderThresholdPercent 键。
      },
    );

    await engine.pull('');

    final after = await repo.getProjectBySyncId(project.syncId!);
    expect(after!.name, '旅遊基金(改名)', reason: '带键的舊欄位应正常覆盖');
    expect(after.incomeIncludedInBudget, isTrue, reason: '缺键不应清空 v56 新欄位');
    expect(after.dailyBudgetEnabled, isTrue, reason: '缺键不应清空 v56 新欄位');
    expect(after.dailyBudgetMode, 'fixed', reason: '缺键不应清空 v56 新欄位');
    expect(after.reminderThresholdPercent, 80, reason: '缺键不应清空 v56 新欄位');
  });

  test('远端 upsert 显式带 v56 新欄位 → 正常覆盖本地值', () async {
    final lid = await seedLedger(syncId: 'ledger-2');
    final id = await repo.createProject(
      ledgerId: lid,
      name: '旅遊基金',
      budgetAmount: 5000,
      reminderThresholdPercent: 80,
    );
    final project = (await repo.getProject(id))!;

    provider.pushFakeChange(
      entityType: 'project',
      entitySyncId: project.syncId!,
      ledgerId: 'ledger-2',
      payload: {
        'syncId': project.syncId,
        'ledgerSyncId': 'ledger-2',
        'name': '旅遊基金',
        'budgetAmount': 5000.0,
        'periodType': 'monthly',
        'carryoverEnabled': false,
        'visibleOnHome': true,
        'enabled': true,
        'sortOrder': 0,
        'incomeIncludedInBudget': true,
        'dailyBudgetEnabled': true,
        'dailyBudgetMode': 'proportional',
        'reminderThresholdPercent': 120,
      },
    );

    await engine.pull('');

    final after = await repo.getProjectBySyncId(project.syncId!);
    expect(after!.incomeIncludedInBudget, isTrue);
    expect(after.dailyBudgetEnabled, isTrue);
    expect(after.dailyBudgetMode, 'proportional');
    expect(after.reminderThresholdPercent, 120);
  });

  test('(insert) 远端新增专案缺 v56 新欄位鍵 → 落 schema 默认值', () async {
    final lid = await seedLedger(syncId: 'ledger-3');

    provider.pushFakeChange(
      entityType: 'project',
      entitySyncId: 'project-new-1',
      ledgerId: 'ledger-3',
      payload: {
        'syncId': 'project-new-1',
        'ledgerSyncId': 'ledger-3',
        'name': '新专案',
        'periodType': 'monthly',
        'carryoverEnabled': false,
        'visibleOnHome': true,
        'enabled': true,
        'sortOrder': 0,
      },
    );

    await engine.pull('');

    final project = await repo.getProjectBySyncId('project-new-1');
    expect(project, isNotNull);
    expect(project!.incomeIncludedInBudget, isFalse);
    expect(project.dailyBudgetEnabled, isFalse);
    expect(project.dailyBudgetMode, 'proportional');
    expect(project.reminderThresholdPercent, isNull);
  });
}
