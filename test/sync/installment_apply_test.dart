// 分期付款(v49 installment_plan/installment_period)同步 apply 路径测试。
//
// 兩者都是 ledger-scope 实体,跟 budget/debt 同款全量 UPSERT 语义(不是
// partial merge)——見 lib/cloud/sync/entity_serializer.dart 相關注释。
//
// 交易的 installmentPlanId(存 syncId)走既有 _applyTransactionChange 路径,
// 这里也顺带测 payload 里的 installmentPlanId 键的恆發/缺鍵不覆蓋語意
// (同 debtId/projectId)。
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

  Future<String> seedCategory({String kind = 'expense'}) async {
    final id = await repo.createCategory(name: '分期', kind: kind, icon: 'x');
    final cat = await repo.getCategoryById(id);
    return cat!.syncId!;
  }

  group('installment_plan', () {
    test('(insert) 远端新增分期計畫 → 本地插入且欄位齊全', () async {
      await seedLedger(syncId: 'ledger-1');
      final categorySyncId = await seedCategory();

      provider.pushFakeChange(
        entityType: 'installment_plan',
        entitySyncId: 'plan-1',
        ledgerId: 'ledger-1',
        payload: {
          'syncId': 'plan-1',
          'ledgerSyncId': 'ledger-1',
          'totalAmount': 1200.0,
          'periods': 12,
          'firstPeriodAt': '2026-01-15T00:00:00Z',
          'accountId': null,
          'categoryId': categorySyncId,
          'note': '手機分期',
          'status': 'active',
          'repaymentMethod': 'equal_principal',
          'interestPeriod': 'monthly',
          'interestRate': 0.0,
          'roundAmounts': true,
          'remainderPosition': 'last',
          'gracePeriodMonths': 0,
        },
      );

      await engine.pull('');

      final plan = await repo.getInstallmentPlanBySyncId('plan-1');
      expect(plan, isNotNull);
      expect(plan!.totalAmount, 1200.0);
      expect(plan.periods, 12);
      expect(plan.note, '手機分期');
      expect(plan.status, 'active');
    });

    test('本地分類尚未就緒(categoryId 對不到)→ 跳過,不建孤兒計畫', () async {
      await seedLedger(syncId: 'ledger-2');

      provider.pushFakeChange(
        entityType: 'installment_plan',
        entitySyncId: 'plan-orphan-cat',
        ledgerId: 'ledger-2',
        payload: {
          'syncId': 'plan-orphan-cat',
          'ledgerSyncId': 'ledger-2',
          'totalAmount': 100.0,
          'periods': 2,
          'firstPeriodAt': '2026-01-01T00:00:00Z',
          'categoryId': 'category-not-synced-yet',
        },
      );

      await engine.pull('');

      expect(await repo.getInstallmentPlanBySyncId('plan-orphan-cat'), isNull);
    });

    test('账本本地尚未就緒(ledgerId 對不到)→ 跳過,不建孤兒計畫', () async {
      provider.pushFakeChange(
        entityType: 'installment_plan',
        entitySyncId: 'plan-orphan-ledger',
        ledgerId: 'ledger-not-synced-yet',
        payload: {
          'syncId': 'plan-orphan-ledger',
          'ledgerSyncId': 'ledger-not-synced-yet',
          'totalAmount': 100.0,
          'periods': 2,
          'firstPeriodAt': '2026-01-01T00:00:00Z',
          'categoryId': 'whatever',
        },
      );

      await engine.pull('');

      expect(
          await repo.getInstallmentPlanBySyncId('plan-orphan-ledger'), isNull);
    });

    test('遠端 upsert 全量覆蓋 → note 缺鍵時視為清空(非 partial merge)', () async {
      final lid = await seedLedger(syncId: 'ledger-3');
      final categoryId =
          await repo.createCategory(name: '分期', kind: 'expense', icon: 'x');
      final categorySyncId = (await repo.getCategoryById(categoryId))!.syncId!;

      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
        note: '舊備註',
      );
      final syncId = (await repo.getInstallmentPlan(planId))!.syncId!;

      provider.pushFakeChange(
        entityType: 'installment_plan',
        entitySyncId: syncId,
        ledgerId: 'ledger-3',
        payload: {
          'syncId': syncId,
          'ledgerSyncId': 'ledger-3',
          'totalAmount': 300.0,
          'periods': 3,
          'firstPeriodAt': '2026-01-01T00:00:00Z',
          'categoryId': categorySyncId,
          // 故意不帶 note 鍵。
          'status': 'active',
        },
      );

      await engine.pull('');

      final plan = await repo.getInstallmentPlanBySyncId(syncId);
      expect(plan!.note, isNull);
    });

    test('(delete) 遠端刪除分期計畫 → 本地對應行被移除', () async {
      final lid = await seedLedger(syncId: 'ledger-4');
      final categoryId =
          await repo.createCategory(name: '分期', kind: 'expense', icon: 'x');
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 100,
        periods: 2,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final syncId = (await repo.getInstallmentPlan(planId))!.syncId!;

      provider.pushFakeChange(
        entityType: 'installment_plan',
        entitySyncId: syncId,
        ledgerId: 'ledger-4',
        action: 'delete',
      );

      await engine.pull('');

      expect(await repo.getInstallmentPlanBySyncId(syncId), isNull);
    });
  });

  // ============================================
  // 問題 A3(2026-09-03,見
  // docs/changes/2026-09-03-installment-tracking-delete-sync-fixes.md 對
  // 「分期計畫刪除後單筆交易刪不掉」的根因調查):`applyRemoteChange` 對所有
  // entity type 的 upsert 都先檢查本地是否有尚未推送的 delete change,有的
  // 話跳過這次 upsert(避免本地剛刪除、還沒推送成功時跑了一次 pull,把
  // server 上還不知道這條刪除的舊版資料複活回本地)。這是通用修法,這裡拿
  // installment_plan 當代表案例驗證。
  // ============================================
  group('問題 A3:pull 應用前檢查本地 pending delete,避免復活剛刪除的實體', () {
    test('本地剛刪除計畫但還沒推送成功時,遠端 upsert(舊版資料)不會把它複活回來',
        () async {
      final lid = await seedLedger(syncId: 'ledger-5');
      final categoryId =
          await repo.createCategory(name: '分期', kind: 'expense', icon: 'x');
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final syncId = (await repo.getInstallmentPlan(planId))!.syncId!;
      final categorySyncId = (await repo.getCategoryById(categoryId))!.syncId!;

      // 模擬「本地剛刪除、還沒推送成功」——deleteInstallmentPlan(repo 帶
      // changeTracker)會記一條 delete change,這個測試不呼叫 engine.push,
      // 所以那條 change 的 pushedAt 一直是 null。
      await repo.deleteInstallmentPlan(planId);
      expect(await repo.getInstallmentPlanBySyncId(syncId), isNull);

      // 這時候跑了一次 pull,拿到 server 上這個實體的舊版 upsert(server 還
      // 不知道這條本地 delete)。
      provider.pushFakeChange(
        entityType: 'installment_plan',
        entitySyncId: syncId,
        ledgerId: 'ledger-5',
        payload: {
          'syncId': syncId,
          'ledgerSyncId': 'ledger-5',
          'totalAmount': 300.0,
          'periods': 3,
          'firstPeriodAt': '2026-01-01T00:00:00Z',
          'categoryId': categorySyncId,
          'status': 'active',
        },
      );

      await engine.pull('');

      // 沒有這次的通用修法之前,這裡會把剛刪除的計畫複活回來——這正是使用者
      // 回報「刪除分期後單筆交易刪不掉」背後懷疑的根因之一。
      expect(await repo.getInstallmentPlanBySyncId(syncId), isNull,
          reason: '本地有尚未推送的 delete change 時,pull 不應該把它複活回來');
    });

    test('本地那條 delete change 一旦標記已推送,之後對同一 syncId 的遠端 upsert 就能正常應用(不是永久卡死)',
        () async {
      final lid = await seedLedger(syncId: 'ledger-6');
      final categoryId =
          await repo.createCategory(name: '分期', kind: 'expense', icon: 'x');
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final syncId = (await repo.getInstallmentPlan(planId))!.syncId!;
      final categorySyncId = (await repo.getCategoryById(categoryId))!.syncId!;

      await repo.deleteInstallmentPlan(planId);

      // 模擬這條 delete change 已經成功推送(正常 push 流程會做的事,這裡
      // 不跑真的 push,直接標記)。
      final unpushed = await changeTracker.getUnpushedChanges();
      await changeTracker.markPushed(unpushed.map((c) => c.id).toList());

      provider.pushFakeChange(
        entityType: 'installment_plan',
        entitySyncId: syncId,
        ledgerId: 'ledger-6',
        payload: {
          'syncId': syncId,
          'ledgerSyncId': 'ledger-6',
          'totalAmount': 900.0,
          'periods': 9,
          'firstPeriodAt': '2026-02-01T00:00:00Z',
          'categoryId': categorySyncId,
          'status': 'active',
        },
      );

      await engine.pull('');

      final plan = await repo.getInstallmentPlanBySyncId(syncId);
      expect(plan, isNotNull,
          reason: '本地 delete change 已推送成功後,不應該再擋住新的合法 upsert');
      expect(plan!.totalAmount, 900.0);
    });
  });

  group('installment_period', () {
    test('(insert) 远端新增期數明細 → 本地插入,txId 反查到本地交易 id', () async {
      final lid = await seedLedger(syncId: 'ledger-5');
      final txId = await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 100,
        happenedAt: DateTime(2026, 1, 15),
        syncId: 'tx-period-1',
      );

      provider.pushFakeChange(
        entityType: 'installment_period',
        entitySyncId: 'period-1',
        ledgerId: 'ledger-5',
        payload: {
          'syncId': 'period-1',
          'planId': 'plan-xyz',
          'periodNo': 1,
          'dueAt': '2026-01-15T00:00:00Z',
          'principalAmount': 100.0,
          'interestAmount': 0.0,
          'totalAmount': 100.0,
          'status': 'generated',
          'txId': 'tx-period-1',
        },
      );

      await engine.pull('');

      final period = await (db.select(db.installmentPeriods)
            ..where((t) => t.syncId.equals('period-1')))
          .getSingle();
      expect(period.planSyncId, 'plan-xyz');
      expect(period.periodNo, 1);
      expect(period.principalAmount, 100.0);
      expect(period.txId, txId);
    });

    test('txId 對不到本地交易 → 落地為 null,不阻擋 period 本身插入', () async {
      await seedLedger(syncId: 'ledger-6');

      provider.pushFakeChange(
        entityType: 'installment_period',
        entitySyncId: 'period-2',
        ledgerId: 'ledger-6',
        payload: {
          'syncId': 'period-2',
          'planId': 'plan-xyz',
          'periodNo': 1,
          'dueAt': '2026-01-15T00:00:00Z',
          'principalAmount': 50.0,
          'interestAmount': 0.0,
          'totalAmount': 50.0,
          'status': 'generated',
          'txId': 'tx-not-synced-yet',
        },
      );

      await engine.pull('');

      final period = await (db.select(db.installmentPeriods)
            ..where((t) => t.syncId.equals('period-2')))
          .getSingle();
      expect(period.txId, isNull);
    });

    test('(delete) 遠端刪除期數 → 本地對應行被移除', () async {
      await seedLedger(syncId: 'ledger-7');
      provider.pushFakeChange(
        entityType: 'installment_period',
        entitySyncId: 'period-3',
        ledgerId: 'ledger-7',
        payload: {
          'syncId': 'period-3',
          'planId': 'plan-xyz',
          'periodNo': 1,
          'dueAt': '2026-01-15T00:00:00Z',
          'principalAmount': 50.0,
          'interestAmount': 0.0,
          'totalAmount': 50.0,
        },
      );
      await engine.pull('');
      expect(
          await (db.select(db.installmentPeriods)
                ..where((t) => t.syncId.equals('period-3')))
              .getSingleOrNull(),
          isNotNull);

      provider.pushFakeChange(
        entityType: 'installment_period',
        entitySyncId: 'period-3',
        ledgerId: 'ledger-7',
        action: 'delete',
      );
      await engine.pull('');

      expect(
          await (db.select(db.installmentPeriods)
                ..where((t) => t.syncId.equals('period-3')))
              .getSingleOrNull(),
          isNull);
    });
  });

  group('transaction payload installmentPlanId', () {
    test('遠端交易帶 installmentPlanId → 正確落地成 installmentPlanSyncId', () async {
      await seedLedger(syncId: 'ledger-8');

      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: 'tx-installment-1',
        ledgerId: 'ledger-8',
        payload: {
          'syncId': 'tx-installment-1',
          'type': 'expense',
          'amount': 100.0,
          'happenedAt': '2026-02-01T00:00:00Z',
          'ledgerSyncId': 'ledger-8',
          'categoryName': null,
          'categoryKind': null,
          'accountName': '',
          'accountId': '',
          'fromAccountName': '',
          'fromAccountId': '',
          'toAccountName': '',
          'toAccountId': '',
          'installmentPlanId': 'plan-abc',
        },
      );

      await engine.pull('');

      final tx = await (db.select(db.transactions)
            ..where((t) => t.syncId.equals('tx-installment-1')))
          .getSingle();
      expect(tx.installmentPlanSyncId, 'plan-abc');
    });

    test('缺 installmentPlanId 鍵 → 不覆蓋本地已有的分期關聯', () async {
      final lid = await seedLedger(syncId: 'ledger-9');
      final txId = await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 50,
        happenedAt: DateTime(2026, 1, 1),
      );
      // 先手動打上本地分期關聯(模擬這筆交易是分期計畫生成的一期)。
      await (db.update(db.transactions)..where((t) => t.id.equals(txId)))
          .write(const TransactionsCompanion(
        installmentPlanSyncId: Value('plan-keep'),
      ));
      final tx = await repo.getTransactionById(txId);
      final syncId = tx!.syncId!;

      provider.pushFakeChange(
        entityType: 'transaction',
        entitySyncId: syncId,
        ledgerId: 'ledger-9',
        payload: {
          'syncId': syncId,
          'type': 'expense',
          'amount': 50.0,
          'happenedAt': '2026-01-01T00:00:00Z',
          'ledgerSyncId': 'ledger-9',
          'categoryName': null,
          'categoryKind': null,
          'accountName': '',
          'accountId': '',
          'fromAccountName': '',
          'fromAccountId': '',
          'toAccountName': '',
          'toAccountId': '',
          // 故意不帶 installmentPlanId 鍵。
        },
      );

      await engine.pull('');

      final updated = await (db.select(db.transactions)
            ..where((t) => t.syncId.equals(syncId)))
          .getSingle();
      expect(updated.installmentPlanSyncId, 'plan-keep');
    });
  });
}
