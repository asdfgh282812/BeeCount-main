// 分期付款(v49)Repository 層測試:建立計畫生成正確期數+交易、§1.4 業務規則
// 校驗(分類必填由 Dart 簽名強制、account_group 子卡拒絕、金額/期數/利率/
// 寬限期範圍)、getInstallmentPlansWithStatus 的 paidPeriods/nextPeriodAt/
// periodAmount 即時算公式、整筆刪除連已發生期的交易一併刪。

import 'package:drift/drift.dart' as d;
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/installment_repository.dart';
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

  Future<int> seedCategory() {
    return repo.createCategory(name: '分期消費', kind: 'expense', icon: 'default');
  }

  Future<int> seedAccount({String? parentAccountId, String? syncId}) {
    return db.into(db.accounts).insert(AccountsCompanion.insert(
          ledgerId: 0,
          name: '信用卡',
          type: const d.Value('credit_card'),
          currency: const d.Value('CNY'),
          parentAccountId: d.Value(parentAccountId),
          syncId: d.Value(syncId),
        ));
  }

  test('建立計畫:等額本金/無息/12期 → 生成12筆交易+12筆period,金額正確且互相連結', () async {
    final lid = await seedLedger();
    final categoryId = await seedCategory();
    final accountId = await seedAccount();
    final firstPeriodAt = DateTime.utc(2026, 1, 15);

    final planId = await repo.createInstallmentPlan(
      ledgerId: lid,
      totalAmount: 1200,
      periods: 12,
      firstPeriodAt: firstPeriodAt,
      accountId: accountId,
      categoryId: categoryId,
      repaymentMethod: 'equal_principal',
      interestRate: 0.0,
    );

    final plan = await repo.getInstallmentPlan(planId);
    expect(plan, isNotNull);
    expect(plan!.syncId, isNotNull);
    expect(plan.status, kInstallmentPlanStatusActive);
    expect(plan.totalAmount, 1200);
    expect(plan.periods, 12);

    final periods = await repo.getInstallmentPeriods(planId);
    expect(periods, hasLength(12));
    expect(periods.every((p) => p.principalAmount == 100.0), isTrue);
    expect(periods.every((p) => p.interestAmount == 0.0), isTrue);
    expect(periods.every((p) => p.status == kInstallmentPeriodStatusGenerated),
        isTrue);
    // periodNo 從 1 開始,依序遞增。
    expect(periods.map((p) => p.periodNo).toList(),
        List.generate(12, (i) => i + 1));

    final txs = await (db.select(db.transactions)
          ..where((t) => t.installmentPlanSyncId.equals(plan.syncId!)))
        .get();
    expect(txs, hasLength(12));
    expect(txs.every((t) => t.type == 'expense'), isTrue);
    expect(txs.every((t) => t.amount == 100.0), isTrue);
    expect(txs.every((t) => t.categoryId == categoryId), isTrue);
    expect(txs.every((t) => t.accountId == accountId), isTrue);

    // 每個 period.txId 都能反查回一筆屬於同一計畫的交易。
    for (final p in periods) {
      expect(p.txId, isNotNull);
      final tx = txs.firstWhere((t) => t.id == p.txId);
      expect(tx.amount, p.totalAmount);
      expect(tx.happenedAt, p.dueAt);
    }
  });

  test(
      'accountId 可以是合併帳單群組的子卡(AccountCardPicker 本來就只能選子卡,'
      '不能選群組主帳戶,見 2026-09-03-installment-tracking-ux-fixes.md)', () async {
    final lid = await seedLedger();
    final categoryId = await seedCategory();
    final parentAccountId = 'parent-sync-id';
    final subCardId = await seedAccount(parentAccountId: parentAccountId);

    final planId = await repo.createInstallmentPlan(
      ledgerId: lid,
      totalAmount: 1200,
      periods: 12,
      firstPeriodAt: DateTime.utc(2026, 1, 15),
      accountId: subCardId,
      categoryId: categoryId,
    );
    final plan = await repo.getInstallmentPlan(planId);
    expect(plan!.accountId, subCardId);
  });

  test('accountId 可以是一般帳戶或留空', () async {
    final lid = await seedLedger();
    final categoryId = await seedCategory();

    // 留空 accountId 應該正常建立。
    final planId = await repo.createInstallmentPlan(
      ledgerId: lid,
      totalAmount: 600,
      periods: 6,
      firstPeriodAt: DateTime.utc(2026, 1, 1),
      categoryId: categoryId,
    );
    final plan = await repo.getInstallmentPlan(planId);
    expect(plan!.accountId, isNull);
  });

  test(
      '業務規則校驗:totalAmount/periods/interestRate/gracePeriodMonths 不合法時拋 ArgumentError',
      () async {
    final lid = await seedLedger();
    final categoryId = await seedCategory();

    expect(
      () => repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 0,
        periods: 12,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      ),
      throwsArgumentError,
      reason: 'totalAmount 必须 > 0',
    );

    expect(
      () => repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1200,
        periods: 601,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      ),
      throwsArgumentError,
      reason: 'periods 上限 600',
    );

    expect(
      () => repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1200,
        periods: 0,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      ),
      throwsArgumentError,
      reason: 'periods 下限 1',
    );

    expect(
      () => repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1200,
        periods: 12,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
        interestRate: -0.1,
      ),
      throwsArgumentError,
      reason: 'interestRate 必须 >= 0',
    );

    expect(
      () => repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1200,
        periods: 12,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
        gracePeriodMonths: 12,
      ),
      throwsArgumentError,
      reason: 'gracePeriodMonths 必须 < periods',
    );
  });

  test(
      'getInstallmentPlansWithStatus:部分期數已到期 → paidPeriods/nextPeriodAt/periodAmount 正確',
      () async {
    final lid = await seedLedger();
    final categoryId = await seedCategory();
    final now = DateTime.now();
    // 第一期 20 天前到期(已過去);第二期 +1 個月(至少 8 天後,穩定落在未來)。
    final firstPeriodAt = now.subtract(const Duration(days: 20));

    final planId = await repo.createInstallmentPlan(
      ledgerId: lid,
      totalAmount: 600,
      periods: 6,
      firstPeriodAt: firstPeriodAt,
      categoryId: categoryId,
      repaymentMethod: 'equal_principal',
    );

    final withStatus = await repo.getInstallmentPlanWithStatus(planId);
    expect(withStatus, isNotNull);
    expect(withStatus!.paidPeriods, 1,
        reason: '只有第一期的 dueAt 落在過去(20天前),其餘 5 期都還沒到期');
    final periods = await repo.getInstallmentPeriods(planId);
    expect(withStatus.nextPeriodAt, periods[1].dueAt);
    expect(withStatus.periodAmount, periods[1].totalAmount);
  });

  test('getInstallmentPlansWithStatus:全部期數都已過去 → 退回最後一期顯示,不是 null', () async {
    final lid = await seedLedger();
    final categoryId = await seedCategory();
    final now = DateTime.now();
    final firstPeriodAt = now.subtract(const Duration(days: 400));

    final planId = await repo.createInstallmentPlan(
      ledgerId: lid,
      totalAmount: 300,
      periods: 3,
      firstPeriodAt: firstPeriodAt,
      categoryId: categoryId,
    );

    final withStatus = await repo.getInstallmentPlanWithStatus(planId);
    final periods = await repo.getInstallmentPeriods(planId);
    expect(withStatus!.paidPeriods, 3);
    expect(withStatus.nextPeriodAt, periods.last.dueAt);
    expect(withStatus.periodAmount, periods.last.totalAmount);
  });

  test('getInstallmentPlansWithStatus:active 排在 settled/terminated 前面',
      () async {
    final lid = await seedLedger();
    final categoryId = await seedCategory();

    final activeId = await repo.createInstallmentPlan(
      ledgerId: lid,
      totalAmount: 300,
      periods: 3,
      firstPeriodAt: DateTime.utc(2020, 1, 1),
      categoryId: categoryId,
    );
    final settledId = await repo.createInstallmentPlan(
      ledgerId: lid,
      totalAmount: 300,
      periods: 3,
      firstPeriodAt: DateTime.utc(2021, 1, 1),
      categoryId: categoryId,
    );
    await (db.update(db.installmentPlans)..where((t) => t.id.equals(settledId)))
        .write(const InstallmentPlansCompanion(
      status: d.Value(kInstallmentPlanStatusSettled),
    ));

    final list = await repo.getInstallmentPlansWithStatus(lid);
    expect(list, hasLength(2));
    expect(list.first.plan.id, activeId);
    expect(list.last.plan.id, settledId);
  });

  test('deleteInstallmentPlan:整筆刪除連已發生期的交易也一併刪(跟子專案2的 terminateFuture 不對稱)',
      () async {
    final lid = await seedLedger();
    final categoryId = await seedCategory();
    final now = DateTime.now();
    // 讓部分期數已到期、部分還沒,驗證「已發生期」也一起被刪(不是只刪未來期)。
    final firstPeriodAt = now.subtract(const Duration(days: 400));

    final planId = await repo.createInstallmentPlan(
      ledgerId: lid,
      totalAmount: 300,
      periods: 3,
      firstPeriodAt: firstPeriodAt,
      categoryId: categoryId,
    );
    final plan = (await repo.getInstallmentPlan(planId))!;
    final planSyncId = plan.syncId!;

    final txsBefore = await (db.select(db.transactions)
          ..where((t) => t.installmentPlanSyncId.equals(planSyncId)))
        .get();
    expect(txsBefore, hasLength(3));

    await repo.deleteInstallmentPlan(planId);

    expect(await repo.getInstallmentPlan(planId), isNull);
    expect(await repo.getInstallmentPeriods(planId), isEmpty);
    final txsAfter = await (db.select(db.transactions)
          ..where((t) => t.installmentPlanSyncId.equals(planSyncId)))
        .get();
    expect(txsAfter, isEmpty, reason: '整筆刪除要連已發生期的交易也一併刪,不留孤兒交易');
  });

  test('deleteInstallmentPlan:計畫不存在時安靜返回,不拋錯', () async {
    await repo.deleteInstallmentPlan(999999);
    // 不拋錯即通過。
  });

  // ============================================
  // 子專案 2:狀態變更操作。
  // ============================================

  Future<void> setPeriodDueAt(int periodId, DateTime dueAt) async {
    await (db.update(db.installmentPeriods)
          ..where((t) => t.id.equals(periodId)))
        .write(InstallmentPeriodsCompanion(dueAt: d.Value(dueAt)));
  }

  Future<void> markOverridden(int periodId) async {
    await (db.update(db.installmentPeriods)
          ..where((t) => t.id.equals(periodId)))
        .write(const InstallmentPeriodsCompanion(
      status: d.Value(kInstallmentPeriodStatusOverridden),
    ));
  }

  Future<void> setPeriodPrincipal(int periodId, double principal) async {
    await (db.update(db.installmentPeriods)
          ..where((t) => t.id.equals(periodId)))
        .write(InstallmentPeriodsCompanion(
      principalAmount: d.Value(principal),
      totalAmount: d.Value(principal), // 測試用途,interest 恆為0時 total=principal
    ));
  }

  group('updatePeriodOverride', () {
    Future<int> seedFixedInterestPlan(int lid, int categoryId) {
      return repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1200,
        periods: 12,
        firstPeriodAt: DateTime.utc(2026, 1, 15),
        categoryId: categoryId,
        repaymentMethod: 'fixed_interest',
        interestPeriod: 'monthly',
        interestRate: 0.12,
      );
    }

    test('帶 amount:利息不變,本金=新總額-利息', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await seedFixedInterestPlan(lid, categoryId);
      final periods = await repo.getInstallmentPeriods(planId);
      final first = periods.first; // principal=100, interest=12, total=112
      expect(first.principalAmount, 100);
      expect(first.interestAmount, 12);

      await repo.updatePeriodOverride(first.id, amount: 150);

      final updated = (await repo.getInstallmentPeriods(planId))
          .firstWhere((p) => p.id == first.id);
      expect(updated.status, kInstallmentPeriodStatusOverridden);
      expect(updated.totalAmount, 150);
      expect(updated.interestAmount, 12, reason: '利息不變');
      expect(updated.principalAmount, 138, reason: '本金 = 新總額(150) - 利息(12)');

      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(updated.txId!)))
          .getSingle();
      expect(tx.amount, 150);
    });

    test('amount 小於 interest 時本金 clamp 到 0(不是負數)', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await seedFixedInterestPlan(lid, categoryId);
      final first = (await repo.getInstallmentPeriods(planId)).first;

      await repo.updatePeriodOverride(first.id, amount: 5);

      final updated = (await repo.getInstallmentPeriods(planId))
          .firstWhere((p) => p.id == first.id);
      expect(updated.totalAmount, 5);
      expect(updated.principalAmount, 0);
    });

    test('只帶 dueAt:連動更新到期日跟交易 happenedAt,金額不變', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await seedFixedInterestPlan(lid, categoryId);
      final first = (await repo.getInstallmentPeriods(planId)).first;
      final newDueAt = DateTime.utc(2026, 2, 1);

      await repo.updatePeriodOverride(first.id, dueAt: newDueAt);

      final updated = (await repo.getInstallmentPeriods(planId))
          .firstWhere((p) => p.id == first.id);
      // Drift 的 dateTime 欄位讀回來是本地時區旗標(isUtc=false),即使儲存的
      // 是同一個時間點——DateTime.== 連 isUtc 旗標都比,所以這裡用
      // isAtSameMomentAs(只比較時間點本身)。
      expect(updated.dueAt.isAtSameMomentAs(newDueAt), isTrue);
      expect(updated.totalAmount, 112, reason: '沒帶 amount,金額不變');
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(updated.txId!)))
          .getSingle();
      expect(tx.happenedAt.isAtSameMomentAs(newDueAt), isTrue);
    });

    test('只帶 note:只更新關聯交易備註,金額/到期日不變(但 period 仍標記 overridden)', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await seedFixedInterestPlan(lid, categoryId);
      final first = (await repo.getInstallmentPeriods(planId)).first;
      final originalDueAt = first.dueAt;

      await repo.updatePeriodOverride(first.id, note: '手動備註');

      final updated = (await repo.getInstallmentPeriods(planId))
          .firstWhere((p) => p.id == first.id);
      expect(updated.status, kInstallmentPeriodStatusOverridden);
      expect(updated.totalAmount, 112);
      expect(updated.dueAt, originalDueAt);
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(updated.txId!)))
          .getSingle();
      expect(tx.note, '手動備註');
    });

    test('periodId 不存在時拋 StateError', () async {
      await expectLater(
          repo.updatePeriodOverride(999999, amount: 10), throwsStateError);
    });
  });

  group('rebalanceFrom', () {
    test('§0 核心不變量:範圍內混有 overridden 期不會被重算隱性挪用本金', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1200,
        periods: 12,
        firstPeriodAt: DateTime.utc(2026, 1, 15),
        categoryId: categoryId,
        repaymentMethod: 'equal_principal',
        interestRate: 0.0,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      expect(periods.every((p) => p.principalAmount == 100), isTrue);

      // 鎖定第5期為 overridden,本金改成跟正常攤還不一樣的 300,驗證重算不會
      // 動它、也不會把它的本金納入可分配池。
      final period5 = periods.firstWhere((p) => p.periodNo == 5);
      await setPeriodPrincipal(period5.id, 300);
      await markOverridden(period5.id);

      await repo.rebalanceFrom(planId, 3, interestRate: 0.0);

      final after = await repo.getInstallmentPeriods(planId);
      final p1 = after.firstWhere((p) => p.periodNo == 1);
      final p2 = after.firstWhere((p) => p.periodNo == 2);
      final p5 = after.firstWhere((p) => p.periodNo == 5);
      final p3 = after.firstWhere((p) => p.periodNo == 3);
      final p12 = after.firstWhere((p) => p.periodNo == 12);

      expect(p1.principalAmount, 100, reason: '重算範圍外(periodNo<3)不動');
      expect(p2.principalAmount, 100, reason: '重算範圍外(periodNo<3)不動');
      expect(p5.principalAmount, 300, reason: 'overridden 期不參與重算,本金不被重新分配');
      expect(p5.status, kInstallmentPeriodStatusOverridden);

      // 剩餘本金 = 1200 - (100+100) - 300(overridden) = 700,分給 9 個
      // targets(periodNo 3,4,6,7,8,9,10,11,12,跳過 5)。
      final targets = after
          .where((p) =>
              p.periodNo >= 3 && p.status != kInstallmentPeriodStatusOverridden)
          .toList();
      expect(targets, hasLength(9));
      final targetsSum = targets.fold(0.0, (sum, p) => sum + p.principalAmount);
      expect(targetsSum, 700,
          reason: '重算結果的本金加總要等於「剩餘待攤還本金」,不能因為 overridden '
              '期被隱性挪用本金而超過或短少');
      expect(p3.principalAmount, isNot(100), reason: '範圍內非 overridden 期要被重算');
      expect(p12.principalAmount, closeTo(700 / 9, 2));
    });

    test('範圍內全部都是 overridden 時沒有可重算的期數,拋 StateError', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      await markOverridden(periods[1].id); // periodNo=2
      await markOverridden(periods[2].id); // periodNo=3

      await expectLater(
          repo.rebalanceFrom(planId, 2, interestRate: 0.0), throwsStateError);
    });

    test('剩餘本金 <=0 時拋 StateError', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      // 把全部本金都鎖進第一期(overridden),periodNo<2 的本金總和已經
      // >= totalAmount,重算池歸零。
      await setPeriodPrincipal(periods[0].id, 300);
      await markOverridden(periods[0].id);

      await expectLater(
          repo.rebalanceFrom(planId, 2, interestRate: 0.0), throwsStateError);
    });

    test('找不到 plan 或 periodNo 時拋 StateError', () async {
      await expectLater(
          repo.rebalanceFrom(999999, 1, interestRate: 0.0), throwsStateError);

      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      await expectLater(
          repo.rebalanceFrom(planId, 999, interestRate: 0.0), throwsStateError);
    });
  });

  /// 建一個 12 期、每期本金 100(equal_principal/無息)的計畫,再把前 6 期的
  /// dueAt 直接改到過去、後 6 期改到未來——刻意不依賴 `firstPeriodAt` +
  /// 月曆加減自然落在哪一天(月份長短不一,靠近月界時不穩定),讓
  /// earlyRepayPrincipal/payoff/terminateFuture 的「已過去 vs 未到期」測試
  /// 案例精確可控。
  Future<({int planId, List<InstallmentPeriod> periods})>
      seedTwelvePeriodPlanWithPastAndFuture(
    int lid,
    int categoryId, {
    String repaymentMethod = 'equal_principal',
    double interestRate = 0.0,
    String interestPeriod = 'monthly',
  }) async {
    final planId = await repo.createInstallmentPlan(
      ledgerId: lid,
      totalAmount: 1200,
      periods: 12,
      firstPeriodAt: DateTime.utc(2020, 1, 15),
      categoryId: categoryId,
      repaymentMethod: repaymentMethod,
      interestPeriod: interestPeriod,
      interestRate: interestRate,
    );
    final periods = await repo.getInstallmentPeriods(planId);
    final now = DateTime.now();
    for (final p in periods) {
      if (p.periodNo <= 6) {
        await setPeriodDueAt(
            p.id, now.subtract(Duration(days: 7 - p.periodNo)));
      } else {
        await setPeriodDueAt(
            p.id, now.add(Duration(days: 30 * (p.periodNo - 6))));
      }
    }
    return (planId: planId, periods: await repo.getInstallmentPeriods(planId));
  }

  group('earlyRepayPrincipal', () {
    test('remainingAfter<=0.005 且沒有 overridden 未來期 → 刪除未來期 + plan 標 settled',
        () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final seed = await seedTwelvePeriodPlanWithPastAndFuture(lid, categoryId);

      // distributableBefore = (1200-600已過去) - 0(無overridden) = 600。
      await repo.earlyRepayPrincipal(seed.planId, paymentAmount: 600);

      final plan = (await repo.getInstallmentPlan(seed.planId))!;
      expect(plan.status, kInstallmentPlanStatusSettled);
      final remaining = await repo.getInstallmentPeriods(seed.planId);
      expect(remaining, hasLength(6), reason: '6 個未來期應該被刪光,只剩 6 個已過去期');
      expect(remaining.every((p) => p.periodNo <= 6), isTrue);

      final repayTxs = await (db.select(db.transactions)
            ..where((t) => t.note.equals('分期部分還本')))
          .get();
      expect(repayTxs, hasLength(1));
      expect(repayTxs.first.amount, 600);
    });

    test(
        'remainingAfter<=0.005 但仍有 overridden 未來期本金 → plan 維持 active,'
        'overridden 期原樣保留', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final seed = await seedTwelvePeriodPlanWithPastAndFuture(lid, categoryId);
      final period10 = seed.periods.firstWhere((p) => p.periodNo == 10);
      await markOverridden(period10.id);

      // 未來 5 個非 overridden 期(7,8,9,11,12)本金合計 500。
      // distributableBefore = 600 - 100(period10) = 500。
      await repo.earlyRepayPrincipal(seed.planId, paymentAmount: 500);

      final plan = (await repo.getInstallmentPlan(seed.planId))!;
      expect(plan.status, kInstallmentPlanStatusActive,
          reason: 'overridden 未來期仍代表真實欠款,不能被靜默結清');
      final remaining = await repo.getInstallmentPeriods(seed.planId);
      // 6 個過去期 + period10(overridden,保留) = 7。
      expect(remaining, hasLength(7));
      expect(
          remaining.any((p) =>
              p.id == period10.id &&
              p.status == kInstallmentPeriodStatusOverridden),
          isTrue);
    });

    test('remainingAfter>0 時對剩餘未來期重新攤還,不刪除', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final seed = await seedTwelvePeriodPlanWithPastAndFuture(lid, categoryId);

      await repo.earlyRepayPrincipal(seed.planId, paymentAmount: 200);

      final after = await repo.getInstallmentPeriods(seed.planId);
      expect(after, hasLength(12), reason: '沒有期數被刪除,只是重新分配金額');
      final futureSum = after
          .where((p) => p.periodNo > 6)
          .fold(0.0, (sum, p) => sum + p.principalAmount);
      expect(futureSum, 400, reason: '600(原可分配) - 200(還本) = 400');
      final pastSum = after
          .where((p) => p.periodNo <= 6)
          .fold(0.0, (sum, p) => sum + p.principalAmount);
      expect(pastSum, 600, reason: '已過去期數不受影響');
    });

    test('paymentAmount 超過可分配本金池時拋 StateError', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final seed = await seedTwelvePeriodPlanWithPastAndFuture(lid, categoryId);

      await expectLater(
          repo.earlyRepayPrincipal(seed.planId, paymentAmount: 601),
          throwsStateError);
    });
  });

  group('payoff', () {
    test('近似應計利息 = 下一個未到期期的原排程利息;不排除 overridden(全部未到期期都刪)', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final seed = await seedTwelvePeriodPlanWithPastAndFuture(
        lid,
        categoryId,
        repaymentMethod: 'fixed_interest',
        interestRate: 0.12,
      );
      // fixed_interest:每期利息恆為 totalAmount*rate = 1200*0.01 = 12。
      final period8 = seed.periods.firstWhere((p) => p.periodNo == 8);
      await markOverridden(period8.id); // 驗證 payoff 仍然刪它

      await repo.payoff(seed.planId);

      final plan = (await repo.getInstallmentPlan(seed.planId))!;
      expect(plan.status, kInstallmentPlanStatusSettled);
      final remaining = await repo.getInstallmentPeriods(seed.planId);
      expect(remaining, hasLength(6),
          reason: '全部未到期期(含 overridden 的 period8)都被刪');
      expect(remaining.every((p) => p.periodNo <= 6), isTrue);

      final settleTxs = await (db.select(db.transactions)
            ..where((t) => t.note.equals('分期提前結清')))
          .get();
      expect(settleTxs, hasLength(1));
      // remainingPrincipal = 1200 - 600(已過去) = 600;
      // accruedInterest = 下一個未到期期(period7)的原排程利息 = 12(近似值,
      // 不是精確按日計息)。
      expect(settleTxs.first.amount, 612);
    });

    test('settleAmount<=0 時不建立交易,只刪期數+標記狀態', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final seed = await seedTwelvePeriodPlanWithPastAndFuture(lid, categoryId);

      // happenedAt 設在全部期數之後,全部期數都算已過去,沒有未到期期,
      // remainingPrincipal=0、accruedInterest=0 → settleAmount=0。
      final farFuture = DateTime.now().add(const Duration(days: 3650));
      await repo.payoff(seed.planId, happenedAt: farFuture);

      final settleTxs = await (db.select(db.transactions)
            ..where((t) => t.note.equals('分期提前結清')))
          .get();
      expect(settleTxs, isEmpty);
      final plan = (await repo.getInstallmentPlan(seed.planId))!;
      expect(plan.status, kInstallmentPlanStatusSettled);
    });
  });

  group('terminateFutureInstallments', () {
    test('刪除未到期期(含 overridden)+ 對應交易,不產生任何交易', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final seed = await seedTwelvePeriodPlanWithPastAndFuture(lid, categoryId);
      final period9 = seed.periods.firstWhere((p) => p.periodNo == 9);
      await markOverridden(period9.id);

      final plan = (await repo.getInstallmentPlan(seed.planId))!;
      final txsBefore = await (db.select(db.transactions)
            ..where((t) => t.installmentPlanSyncId.equals(plan.syncId!)))
          .get();
      expect(txsBefore, hasLength(12));

      await repo.terminateFutureInstallments(seed.planId);

      final updatedPlan = (await repo.getInstallmentPlan(seed.planId))!;
      expect(updatedPlan.status, kInstallmentPlanStatusTerminated);
      final remaining = await repo.getInstallmentPeriods(seed.planId);
      expect(remaining, hasLength(6));
      expect(remaining.every((p) => p.periodNo <= 6), isTrue);

      final txsAfter = await (db.select(db.transactions)
            ..where((t) => t.installmentPlanSyncId.equals(plan.syncId!)))
          .get();
      expect(txsAfter, hasLength(6), reason: '6 個未到期期的交易應該一併被刪');
      expect(txsAfter.length, lessThan(txsBefore.length),
          reason: 'terminateFutureInstallments 只刪,不會新增任何交易(跟 '
              'earlyRepayPrincipal/payoff 不同,兩者都會產生一筆結算交易)');
    });
  });

  group('deleteTransaction 攔截分期交易(見 InstallmentManagedTransactionException)',
      () {
    test('一般 deleteTransaction 呼叫刪分期期數交易時被攔下,交易不會被刪', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      final txId = periods.first.txId!;

      await expectLater(
        repo.deleteTransaction(txId),
        throwsA(isA<InstallmentManagedTransactionException>()),
      );

      final stillThere = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      expect(stillThere, isNotNull, reason: '被攔下的刪除不應該真的執行');
    });

    test('一般交易(非分期)透過 deleteTransaction 刪除不受影響', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final txId = await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 50,
        categoryId: categoryId,
        happenedAt: DateTime.utc(2026, 1, 1),
      );

      await repo.deleteTransaction(txId);

      final gone = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      expect(gone, isNull);
    });

    test('repo 內部狀態變更操作(terminateFutureInstallments)刪期數交易不受此攔截影響', () async {
      // 上面 terminateFutureInstallments 的測試已經驗證了這件事會成功執行
      // (若攔截誤傷了 repo 內部呼叫,那個測試會直接拋
      // InstallmentManagedTransactionException 而失敗)。這裡另外用
      // earlyRepayPrincipal 的刪除分支再驗證一次,涵蓋兩個不同的內部呼叫點。
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final seed = await seedTwelvePeriodPlanWithPastAndFuture(lid, categoryId);

      await expectLater(
        repo.earlyRepayPrincipal(seed.planId, paymentAmount: 600),
        completes,
      );
    });
  });

  // ============================================
  // 子專案 3:退款(見設計文件 §3.3)。
  // ============================================

  group('refundPeriod', () {
    test('預設金額=該期totalAmount、note="分期退款";期數標記refunded;原交易不刪不改', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      final target = periods.first;
      final txId = target.txId!;
      final originalTx = (await repo.getTransactionById(txId))!;

      await repo.refundPeriod(planId, txId);

      final updatedPeriod = (await repo.getInstallmentPeriods(planId))
          .firstWhere((p) => p.id == target.id);
      expect(updatedPeriod.status, kInstallmentPeriodStatusRefunded);

      final unchangedTx = (await repo.getTransactionById(txId))!;
      expect(unchangedTx.amount, originalTx.amount);
      expect(unchangedTx.happenedAt, originalTx.happenedAt);
      expect(
          unchangedTx.installmentPlanSyncId, originalTx.installmentPlanSyncId,
          reason: '原交易(分期期數本身那筆)不受退款影響,依然掛著 installmentPlanSyncId');

      final refundTxs = await repo.getRefundsOf(originalTx.syncId!);
      expect(refundTxs, hasLength(1));
      final refundTx = refundTxs.first;
      expect(refundTx.type, 'income');
      expect(refundTx.amount, target.totalAmount);
      expect(refundTx.note, '分期退款');
      expect(refundTx.accountId, isNull,
          reason:
              '這個計畫建立時沒帶 accountId,退款交易 accountId 用 plan.accountId(此例為 null)');
      expect(refundTx.refundOfSyncId, originalTx.syncId);
      // §3.3 的關鍵要求:退款交易本身刻意不打 installmentPlanSyncId,避免
      // 被 InstallmentManagedTransactionException 誤判成分期交易而擋住。
      expect(refundTx.installmentPlanSyncId, isNull);
    });

    test('amount/note/happenedAt 可覆寫預設值', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final accountId = await seedAccount();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        accountId: accountId,
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      final txId = periods.first.txId!;
      final happenedAt = DateTime.utc(2026, 5, 1);

      await repo.refundPeriod(
        planId,
        txId,
        amount: 40,
        note: '部分退款測試',
        happenedAt: happenedAt,
      );

      final originalTx = (await repo.getTransactionById(txId))!;
      final refundTxs = await repo.getRefundsOf(originalTx.syncId!);
      expect(refundTxs, hasLength(1));
      final refundTx = refundTxs.first;
      expect(refundTx.amount, 40);
      expect(refundTx.note, '部分退款測試');
      // Drift 的 dateTime() 欄位讀回來 isUtc 一律是 false,DateTime.== 連
      // isUtc 旗標都比,要用 isAtSameMomentAs 才對(同子專案 2 踩過的坑,見
      // docs/changes/2026-09-03-installment-tracking-phase2.md)。
      expect(refundTx.happenedAt.isAtSameMomentAs(happenedAt), isTrue);
      expect(refundTx.accountId, accountId,
          reason: 'accountId 用 plan.accountId');
    });

    test('同一期重複退款時拋 StateError,不再建立第二筆退款交易', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      final txId = periods.first.txId!;

      await repo.refundPeriod(planId, txId);
      await expectLater(repo.refundPeriod(planId, txId), throwsStateError);

      final originalTx = (await repo.getTransactionById(txId))!;
      final refundTxs = await repo.getRefundsOf(originalTx.syncId!);
      expect(refundTxs, hasLength(1), reason: '拒絕重複退款,不應該多建一筆');
    });

    test('找不到 plan 或對應期數(txId)時拋 StateError', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      final txId = periods.first.txId!;

      await expectLater(repo.refundPeriod(999999, txId), throwsStateError);
      await expectLater(repo.refundPeriod(planId, 999999), throwsStateError);
    });

    test(
        '退款交易不受 InstallmentManagedTransactionException 攔截:可透過一般 deleteTransaction 刪除',
        () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      final txId = periods.first.txId!;

      await repo.refundPeriod(planId, txId);
      final originalTx = (await repo.getTransactionById(txId))!;
      final refundTx = (await repo.getRefundsOf(originalTx.syncId!)).single;

      // 這是本次要驗證的關鍵行為:退款交易本身沒有 installmentPlanSyncId,
      // 一般 deleteTransaction 入口(同時也是 InstallmentManagedTransaction
      // Exception 攔截的唯一觸發點)能正常刪除它,不會被誤判成「分期計畫
      // 管理的交易」而拋例外擋下。
      await expectLater(repo.deleteTransaction(refundTx.id), completes);
      final gone = await repo.getTransactionById(refundTx.id);
      expect(gone, isNull);

      // 原本那期(退款來源)的交易依然存在、依然掛著 installmentPlanSyncId,
      // 不受這次刪除退款交易影響。
      final stillManaged = await repo.getTransactionById(txId);
      expect(stillManaged, isNotNull);
      expect(stillManaged!.installmentPlanSyncId, isNotNull);
    });
  });

  group('offsetExistingBalance / 帳單分期沖銷(子專案4)', () {
    test('offsetExistingBalance=true 但沒有 accountId 時拋 ArgumentError', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();

      await expectLater(
        repo.createInstallmentPlan(
          ledgerId: lid,
          totalAmount: 100,
          periods: 3,
          firstPeriodAt: DateTime.now().add(const Duration(days: 10)),
          categoryId: categoryId,
          offsetExistingBalance: true,
        ),
        throwsArgumentError,
      );
    });

    test('目前應繳餘額 <= 0.005 時視為無欠款,拋 ArgumentError', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final accountId = await seedAccount(syncId: 'acc-offset-empty');
      // 沒有任何消費交易,目前應繳餘額 = 0。

      await expectLater(
        repo.createInstallmentPlan(
          ledgerId: lid,
          totalAmount: 100,
          periods: 3,
          firstPeriodAt: DateTime.now().add(const Duration(days: 10)),
          accountId: accountId,
          categoryId: categoryId,
          offsetExistingBalance: true,
        ),
        throwsArgumentError,
      );
    });

    test('totalAmount 超過目前應繳餘額時拋 ArgumentError', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final accountId = await seedAccount(syncId: 'acc-offset-exceed');
      final now = DateTime.now();
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 500,
        accountId: accountId,
        happenedAt: now.subtract(const Duration(days: 5)),
      );

      expect(await repo.getCreditCardOffsetableBalance(accountId), 500);

      await expectLater(
        repo.createInstallmentPlan(
          ledgerId: lid,
          totalAmount: 600, // 超過目前欠款 500
          periods: 3,
          firstPeriodAt: now.add(const Duration(days: 25)),
          accountId: accountId,
          categoryId: categoryId,
          offsetExistingBalance: true,
        ),
        throwsArgumentError,
      );
    });

    test('account_group 帳戶目前不支援沖銷,拋 ArgumentError', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final groupId =
          await db.into(db.accounts).insert(AccountsCompanion.insert(
                ledgerId: lid,
                name: '主帳戶',
                type: const d.Value('account_group'),
                syncId: const d.Value('grp-offset-1'),
              ));

      await expectLater(
        repo.createInstallmentPlan(
          ledgerId: lid,
          totalAmount: 100,
          periods: 3,
          firstPeriodAt: DateTime.now().add(const Duration(days: 10)),
          accountId: groupId,
          categoryId: categoryId,
          offsetExistingBalance: true,
        ),
        throwsArgumentError,
      );
    });

    test('沖銷成功:不產生沖銷交易、寫入offsetBreakdownJson、帳單彙總計算扣掉避免重複計入', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final accountId = await seedAccount(syncId: 'acc-offset-ok');
      final now = DateTime.now();
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 1000,
        accountId: accountId,
        happenedAt: now.subtract(const Duration(days: 5)),
      );

      final dueBefore = await repo.getCreditCardOffsetableBalance(accountId);
      expect(dueBefore, 1000);
      final txCountBefore = await (db.select(db.transactions)
            ..where((t) => t.accountId.equals(accountId)))
          .get();
      expect(txCountBefore, hasLength(1));

      // firstPeriodAt 選在未來,確保 10 期分期交易全部還沒到期——這樣才能
      // 乾淨驗證「沖銷後應繳餘額歸零」,不會被剛好到期的分期期數交易干擾
      // (那是另一個獨立行為:分期期數本來就會隨時間到期而正常疊加應繳)。
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1000,
        periods: 10,
        firstPeriodAt: now.add(const Duration(days: 25)),
        accountId: accountId,
        categoryId: categoryId,
        offsetExistingBalance: true,
      );

      final plan = await repo.getInstallmentPlan(planId);
      expect(plan, isNotNull);
      expect(plan!.offsetBreakdownJson, isNotNull);
      expect(plan.offsetBreakdownJson, contains('acc-offset-ok'));
      expect(plan.offsetBreakdownJson, contains('1000'));

      // 沖銷部分不產生任何交易——帳戶上的交易只多了 10 期分期交易本身,沒有
      // 額外一筆「沖銷」交易。
      final txsAfter = await (db.select(db.transactions)
            ..where((t) => t.accountId.equals(accountId)))
          .get();
      expect(txsAfter, hasLength(1 + 10));

      // 信用卡帳單彙總計算讀取 offsetBreakdownJson 後,不會把這筆已轉分期的
      // 舊欠款重複算進「目前應繳」。
      expect(await repo.getOffsetTotalForAccount(accountId), 1000);
      expect(await repo.getCreditCardOffsetableBalance(accountId), 0);
    });

    test('部分沖銷:totalAmount 可以小於目前欠款,只沖銷實際轉換的部分', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final accountId = await seedAccount(syncId: 'acc-offset-partial');
      final now = DateTime.now();
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 1000,
        accountId: accountId,
        happenedAt: now.subtract(const Duration(days: 5)),
      );

      await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 400,
        periods: 4,
        firstPeriodAt: now.add(const Duration(days: 25)),
        accountId: accountId,
        categoryId: categoryId,
        offsetExistingBalance: true,
      );

      expect(await repo.getOffsetTotalForAccount(accountId), 400);
      // 1000 欠款只沖銷了 400,還剩 600 可以繼續沖銷(或維持一般欠款)。
      expect(await repo.getCreditCardOffsetableBalance(accountId), 600);
    });

    test('刪除分期計畫後,沖銷記錄自動失效(offsetBreakdownJson 隨列一起刪)', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final accountId = await seedAccount(syncId: 'acc-offset-delete');
      final now = DateTime.now();
      await repo.addTransaction(
        ledgerId: lid,
        type: 'expense',
        amount: 800,
        accountId: accountId,
        happenedAt: now.subtract(const Duration(days: 3)),
      );

      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 800,
        periods: 4,
        firstPeriodAt: now.add(const Duration(days: 25)),
        accountId: accountId,
        categoryId: categoryId,
        offsetExistingBalance: true,
      );
      expect(await repo.getOffsetTotalForAccount(accountId), 800);
      expect(await repo.getCreditCardOffsetableBalance(accountId), 0);

      await repo.deleteInstallmentPlan(planId);

      expect(await repo.getInstallmentPlan(planId), isNull);
      expect(await repo.getOffsetTotalForAccount(accountId), 0,
          reason: '整筆刪除計畫連 offsetBreakdownJson 一起刪,沖銷自動失效');
      // 沖銷失效後,原本那 800 元舊欠款(整筆刪除計畫時連分期期數交易也一起
      // 刪了,但沖銷對應的「既有欠款」本來就不是分期交易——它是刪除計畫前
      // 就存在的那筆 800 元原始消費,不受 deleteInstallmentPlan 影響)重新算
      // 回應繳餘額。
      expect(await repo.getCreditCardOffsetableBalance(accountId), 800);
    });
  });

  // ============================================
  // 問題 A 修正(2026-09-03,見
  // docs/changes/2026-09-03-installment-tracking-delete-sync-fixes.md):
  // A2「單純刪除一期」+ A1「plan 已不存在(孤兒)時 deleteTransaction 放行」。
  // ============================================

  group('deletePeriod(問題 A2:單純刪除一期,不重算/不動其他期數金額)', () {
    test('刪除單一期數不影響其他期數金額,對應交易一併刪除', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1200,
        periods: 12,
        firstPeriodAt: DateTime.utc(2026, 1, 15),
        categoryId: categoryId,
        repaymentMethod: 'equal_principal',
        interestRate: 0.0,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      final target = periods.firstWhere((p) => p.periodNo == 5);
      final targetTxId = target.txId!;

      await repo.deletePeriod(planId, target.id);

      final after = await repo.getInstallmentPeriods(planId);
      expect(after, hasLength(11), reason: '只刪掉這一期,其餘 11 期還在');
      expect(after.any((p) => p.periodNo == 5), isFalse);
      // 其他期數的本金/總額完全不變(不重算,不同於 rebalanceFrom 那種財務
      // 操作)。
      for (final p in after) {
        expect(p.principalAmount, 100.0,
            reason: 'periodNo=${p.periodNo} 的本金不應該被這次刪除動到');
      }
      final txGone = await (db.select(db.transactions)
            ..where((t) => t.id.equals(targetTxId)))
          .getSingleOrNull();
      expect(txGone, isNull, reason: '對應交易應該一併刪除');

      final plan = await repo.getInstallmentPlan(planId);
      expect(plan, isNotNull, reason: '計畫還有其他 11 期,不應該被連帶刪除');
    });

    test('刪除最後一期後計畫已無任何期數,連帶刪除 plan 本身', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);

      await repo.deletePeriod(planId, periods[0].id);
      await repo.deletePeriod(planId, periods[1].id);
      expect(await repo.getInstallmentPlan(planId), isNotNull,
          reason: '還剩最後一期,plan 應該還在');

      await repo.deletePeriod(planId, periods[2].id);

      expect(await repo.getInstallmentPlan(planId), isNull,
          reason: '0 期的空殼計畫應該被自然收尾一併刪除');
      expect(await repo.getInstallmentPeriods(planId), isEmpty);
    });

    test('找不到 plan 或 period 時拋 StateError', () async {
      await expectLater(repo.deletePeriod(999999, 1), throwsStateError);

      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      await expectLater(repo.deletePeriod(planId, 999999), throwsStateError);
    });
  });

  group('deleteTransaction 對「plan 已不存在」的孤兒分期交易放行(問題 A1)', () {
    test('plan 已整筆刪除但交易/period 殘留(孤兒)時,deleteTransaction 直接放行並清掉孤兒 period',
        () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      final txId = periods.first.txId!;
      final periodId = periods.first.id;

      // 模擬「整筆刪除計畫但同步/推送過程中留下孤兒」的情境:直接刪 plan
      // 本身(不透過 deleteInstallmentPlan,那個方法會連帶刪光 period/交易,
      // 這裡刻意繞過它,製造出跟使用者回報一致的殘留狀態)。
      await (db.delete(db.installmentPlans)..where((t) => t.id.equals(planId)))
          .go();

      // plan 已經不存在,一般 deleteTransaction 應該放行,不再拋
      // InstallmentManagedTransactionException。
      await expectLater(repo.deleteTransaction(txId), completes);

      final txGone = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingleOrNull();
      expect(txGone, isNull);

      // 順便清掉指向這筆交易的孤兒 period 列。
      final periodGone = await (db.select(db.installmentPeriods)
            ..where((t) => t.id.equals(periodId)))
          .getSingleOrNull();
      expect(periodGone, isNull, reason: '孤兒 period 應該隨這次刪除一併清掉');
    });

    test('plan 仍存在時,deleteTransaction 依然攔截(維持既有行為)', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 300,
        periods: 3,
        firstPeriodAt: DateTime.utc(2026, 1, 1),
        categoryId: categoryId,
      );
      final periods = await repo.getInstallmentPeriods(planId);
      final txId = periods.first.txId!;

      await expectLater(
        repo.deleteTransaction(txId),
        throwsA(isA<InstallmentManagedTransactionException>()),
      );
    });
  });

  group('getOutstandingPrincipalAllLedgers(首頁「尚有應繳」摘要——問題A的殘留孤兒不該被算進去)', () {
    test('plan 已刪但 period 還在(見上方問題A的殘留孤兒場景)→ 不計入尚有應繳', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      final planId = await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1200,
        periods: 12,
        firstPeriodAt: DateTime.now().add(const Duration(days: 1)),
        categoryId: categoryId,
      );

      // 直接刪 installment_plans 行,模擬「N*2+1 筆 change 推送/拉取之間的
      // 窗口期 race」留下的殘留狀態:plan 沒了,但 period(ledgerId 仍指向
      // 現存帳本)還在,且到期日在未來——這正是使用者實測回報「首頁顯示尚有
      // 應繳,但分期列表已經找不到這個計畫」的成因。
      await (db.delete(db.installmentPlans)..where((t) => t.id.equals(planId)))
          .go();

      final outstanding = await repo.getOutstandingPrincipalAllLedgers();
      expect(outstanding, 0.0, reason: 'plan 已刪的孤兒 period 不該污染首頁摘要卡片的金額');
    });

    test('plan 仍存在,未到期期數的本金正確計入尚有應繳', () async {
      final lid = await seedLedger();
      final categoryId = await seedCategory();
      await repo.createInstallmentPlan(
        ledgerId: lid,
        totalAmount: 1200,
        periods: 12,
        firstPeriodAt: DateTime.now().add(const Duration(days: 1)),
        categoryId: categoryId,
      );

      final outstanding = await repo.getOutstandingPrincipalAllLedgers();
      expect(outstanding, closeTo(1200, 0.01));
    });
  });
}
