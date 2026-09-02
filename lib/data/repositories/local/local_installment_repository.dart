import 'dart:convert';

import 'package:drift/drift.dart' as d;
import 'package:uuid/uuid.dart';

import '../../../services/installment/installment_amortization.dart';
import '../../../utils/credit_card_payment.dart';
import '../../db.dart';
import '../installment_repository.dart';
import 'local_account_repository.dart';

const _uuid = Uuid();

/// 分期付款 Repository 本地實作,基於 Drift。
///
/// 這裡 NOT 直接調 changeTracker;changeTracker 的注入是通過
/// LocalRepository 包装层(lib/data/repositories/local/local_repository.dart)
/// 在 CRUD 前后统一 recordChange,保持跟 debt/budget 的代码结构一致。
class LocalInstallmentRepository implements InstallmentRepository {
  final BeeDatabase db;

  /// 子專案 4(帳單分期沖銷)需要讀信用卡「已消費/已繳款」金額——直接複用
  /// `LocalAccountRepository` 既有、已經被 `credit_card_billing_providers.
  /// dart` 驗證過的查詢方法(`getCreditCardChargedAsOf`/
  /// `getCreditCardPaidTotal`),不重寫一份 SQL。`LocalAccountRepository` 只
  /// 是 `db` 的無狀態包裝(不持有 changeTracker 等外部狀態),這裡另外建一份
  /// 是安全的,不會跟 `LocalRepository._accountRepo` 那份打架。
  final LocalAccountRepository _accountRepo;

  LocalInstallmentRepository(this.db) : _accountRepo = LocalAccountRepository(db);

  @override
  Future<int> createInstallmentPlan({
    required int ledgerId,
    required double totalAmount,
    required int periods,
    required DateTime firstPeriodAt,
    int? accountId,
    required int categoryId,
    String? note,
    String repaymentMethod = 'equal_principal',
    String interestPeriod = 'monthly',
    double interestRate = 0.0,
    bool roundAmounts = true,
    String remainderPosition = 'last',
    int gracePeriodMonths = 0,
    bool offsetExistingBalance = false,
  }) async {
    // §1.4 業務規則校驗——這裡先擋掉 computeInstallmentPeriods 自己不管的
    // periods 上限(600),其餘(periods>=1/interestRate>=0/grace 範圍/
    // repaymentMethod 合法值)交給 computeInstallmentPeriods 自己的驗證,
    // 不重複寫一遍。
    if (totalAmount <= 0) {
      throw ArgumentError('totalAmount must be > 0');
    }
    if (periods < 1 || periods > 600) {
      throw ArgumentError('periods must be between 1 and 600');
    }
    Account? account;
    if (accountId != null) {
      account = await (db.select(db.accounts)
            ..where((a) => a.id.equals(accountId)))
          .getSingleOrNull();
      // 原本這裡照設計文件 §1.4 擋掉「合併帳單群組的子卡」,要求改選群組
      // 主帳戶——但 `AccountCardPicker`(交易表單/分期建立表單共用的帳戶
      // 選擇器)本來就把 `type == 'account_group'` 的主帳戶整個過濾掉,一般
      // 交易/分期都只能選子卡本身,群組主帳戶在這個 App 裡從來不是可選項。
      // 這條校驗因此會擋掉唯一合法的輸入,2026-09-03 移除,子卡跟一般帳戶
      // 同樣允許掛靠分期(見 docs/changes/2026-09-03-installment-tracking-ux-fixes.md)。
    }

    // 子專案 4:帳單分期沖銷。§3.4——把這張卡「目前應繳餘額」轉成這筆分期,
    // 不產生沖銷交易,只把 {accountSyncId: amount} 記進
    // InstallmentPlans.offsetBreakdownJson,供信用卡帳單彙總計算讀取後扣掉
    // (見 InstallmentRepository 介面 docstring)。
    String? offsetBreakdownJson;
    if (offsetExistingBalance) {
      if (accountId == null || account == null) {
        throw ArgumentError('offsetExistingBalance 需要指定 accountId');
      }
      // 目前只支援單一帳戶沖銷,不支援合併帳單群組(account_group)——群組的
      // 「應繳」是多張子卡加總分攤,沖銷分攤演算法對齊 Cloud
      // compute_card_payment_allocations 才能做對,這次先不做(見
      // docs/changes/2026-09-03-installment-tracking-phase4.md 的範圍說明)。
      if (account.type == 'account_group') {
        throw ArgumentError('offsetExistingBalance 目前不支援合併帳單群組,請改選單一信用卡');
      }
      final due = await getCreditCardOffsetableBalance(accountId);
      if (due <= 0.005) {
        throw ArgumentError('這張帳戶目前沒有可沖銷的欠款');
      }
      // 容許 0.01 的浮點誤差,對齐 Cloud
      // `req.total_amount > total_due + 0.01` 的判斷。
      if (totalAmount > due + 0.01) {
        throw ArgumentError('分期總額不能超過目前應繳餘額($due)');
      }
      final offsetKey = account.syncId ?? accountId.toString();
      offsetBreakdownJson = jsonEncode({offsetKey: totalAmount});
    }

    // 攤還排程——計息/取整/寬限期邏輯全部委托給純函式,這裡不重算。
    // computeInstallmentPeriods 自己會驗證 interestRate>=0、
    // 0<=gracePeriodMonths<periods、repaymentMethod/interestPeriod/
    // remainderPosition 是否合法值,不合法拋 ArgumentError,直接讓它往外冒。
    final schedule = computeInstallmentPeriods(
      totalAmount: totalAmount,
      periods: periods,
      firstPeriodAt: firstPeriodAt,
      repaymentMethod: repaymentMethod,
      interestPeriod: interestPeriod,
      interestRate: interestRate,
      roundAmounts: roundAmounts,
      remainderPosition: remainderPosition,
      gracePeriodMonths: gracePeriodMonths,
    );

    final planSyncId = _uuid.v4();

    return db.transaction(() async {
      final now = DateTime.now();
      final planId = await db.into(db.installmentPlans).insert(
            InstallmentPlansCompanion.insert(
              ledgerId: ledgerId,
              totalAmount: totalAmount,
              periods: periods,
              firstPeriodAt: firstPeriodAt,
              accountId: d.Value(accountId),
              categoryId: categoryId,
              note: d.Value(note),
              status: const d.Value(kInstallmentPlanStatusActive),
              repaymentMethod: d.Value(repaymentMethod),
              interestPeriod: d.Value(interestPeriod),
              interestRate: d.Value(interestRate),
              roundAmounts: d.Value(roundAmounts),
              remainderPosition: d.Value(remainderPosition),
              gracePeriodMonths: d.Value(gracePeriodMonths),
              offsetBreakdownJson: d.Value(offsetBreakdownJson),
              syncId: d.Value(planSyncId),
              createdAt: d.Value(now),
              updatedAt: d.Value(now),
            ),
          );

      // 逐期寫入交易 + period——期數上限 600,單一裝置內循序 insert 在一個
      // db.transaction() 裡沒有效能問題;用循序 insert(不是 db.batch)是
      // 因為需要拿到每筆交易的自增 id 回填 InstallmentPeriods.txId。
      for (final period in schedule) {
        final txId = await db.into(db.transactions).insert(
              TransactionsCompanion.insert(
                ledgerId: ledgerId,
                type: 'expense',
                amount: period.totalAmount,
                categoryId: d.Value(categoryId),
                accountId: d.Value(accountId),
                happenedAt: d.Value(period.dueAt),
                note: d.Value(note),
                syncId: d.Value(_uuid.v4()),
                installmentPlanSyncId: d.Value(planSyncId),
              ),
            );
        await db.into(db.installmentPeriods).insert(
              InstallmentPeriodsCompanion.insert(
                ledgerId: ledgerId,
                planSyncId: planSyncId,
                periodNo: period.periodNo,
                dueAt: period.dueAt,
                principalAmount: period.principalAmount,
                interestAmount: period.interestAmount,
                totalAmount: period.totalAmount,
                status: const d.Value(kInstallmentPeriodStatusGenerated),
                txId: d.Value(txId),
                createdAt: d.Value(now),
                updatedAt: d.Value(now),
              ),
            );
      }

      return planId;
    });
  }

  @override
  Future<InstallmentPlan?> getInstallmentPlan(int id) =>
      (db.select(db.installmentPlans)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<InstallmentPlan?> getInstallmentPlanBySyncId(String syncId) =>
      (db.select(db.installmentPlans)..where((t) => t.syncId.equals(syncId)))
          .getSingleOrNull();

  @override
  Future<List<InstallmentPeriod>> getInstallmentPeriods(int planId) async {
    final plan = await getInstallmentPlan(planId);
    if (plan?.syncId == null) return [];
    return (db.select(db.installmentPeriods)
          ..where((t) => t.planSyncId.equals(plan!.syncId!))
          ..orderBy([(t) => d.OrderingTerm.asc(t.periodNo)]))
        .get();
  }

  /// 依 [plan] 算出即時的 paidPeriods/nextPeriodAt/periodAmount。推導公式
  /// 逐行對齐 BeeCount Cloud `routers/read/ledgers.py::list_installment_plans`
  /// (line 1545-1620),見設計文件 §1.1:
  ///
  /// - paidPeriods = 依 dueAt 排序後,`dueAt <= now` 的期數個數(不排除
  ///   refunded——退款是另一個獨立語意維度,不影響「已到期期數」計數)。
  /// - 若存在 `dueAt > now` 的未來期:nextPeriodAt/periodAmount 取第一個
  ///   未來期的 dueAt/totalAmount。
  /// - 否則(全部期數都已過去)退回最後一期顯示,不是 null。
  /// - 理論上不會發生的兜底(plan 沒有任何 period):退回 plan.firstPeriodAt
  ///   / 0。
  Future<InstallmentPlanWithStatus> _withStatus(InstallmentPlan plan) async {
    final periods = await getInstallmentPeriods(plan.id);
    final now = DateTime.now();
    final sorted = [...periods]..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final paidPeriods = sorted.where((p) => !p.dueAt.isAfter(now)).length;
    final future = sorted.where((p) => p.dueAt.isAfter(now)).toList();

    final DateTime nextPeriodAt;
    final double periodAmount;
    if (future.isNotEmpty) {
      nextPeriodAt = future.first.dueAt;
      periodAmount = future.first.totalAmount;
    } else if (sorted.isNotEmpty) {
      nextPeriodAt = sorted.last.dueAt;
      periodAmount = sorted.last.totalAmount;
    } else {
      nextPeriodAt = plan.firstPeriodAt;
      periodAmount = 0;
    }

    return InstallmentPlanWithStatus(
      plan: plan,
      paidPeriods: paidPeriods,
      nextPeriodAt: nextPeriodAt,
      periodAmount: periodAmount,
    );
  }

  @override
  Future<List<InstallmentPlanWithStatus>> getInstallmentPlansWithStatus(
      int ledgerId) async {
    final plans = await (db.select(db.installmentPlans)
          ..where((t) => t.ledgerId.equals(ledgerId)))
        .get();
    // active 排前面,狀態相同時依 firstPeriodAt 由新到舊。
    plans.sort((a, b) {
      final aActive = a.status == kInstallmentPlanStatusActive;
      final bActive = b.status == kInstallmentPlanStatusActive;
      if (aActive != bActive) return aActive ? -1 : 1;
      return b.firstPeriodAt.compareTo(a.firstPeriodAt);
    });
    return [for (final plan in plans) await _withStatus(plan)];
  }

  @override
  Future<InstallmentPlanWithStatus?> getInstallmentPlanWithStatus(
      int id) async {
    final plan = await getInstallmentPlan(id);
    if (plan == null) return null;
    return _withStatus(plan);
  }

  @override
  Future<void> deleteInstallmentPlan(int id) async {
    final plan = await getInstallmentPlan(id);
    if (plan == null) return;
    await db.transaction(() async {
      if (plan.syncId != null) {
        await (db.delete(db.transactions)
              ..where((t) => t.installmentPlanSyncId.equals(plan.syncId!)))
            .go();
        await (db.delete(db.installmentPeriods)
              ..where((t) => t.planSyncId.equals(plan.syncId!)))
            .go();
      }
      await (db.delete(db.installmentPlans)..where((t) => t.id.equals(id)))
          .go();
    });
  }

  @override
  Stream<List<InstallmentPlan>> watchInstallmentPlans(int ledgerId) {
    return (db.select(db.installmentPlans)
          ..where((t) => t.ledgerId.equals(ledgerId)))
        .watch();
  }

  @override
  Future<double> getOutstandingPrincipalAllLedgers() async {
    final now = DateTime.now();
    final periods = await db.select(db.installmentPeriods).get();
    var total = 0.0;
    for (final p in periods) {
      if (p.dueAt.isAfter(now)) total += p.principalAmount;
    }
    return total;
  }

  // ============================================
  // 子專案 4:信用卡帳單分期沖銷(見設計文件 §3.4)。
  // ============================================

  @override
  Future<double> getOffsetTotalForAccount(int accountId) async {
    final account = await (db.select(db.accounts)
          ..where((a) => a.id.equals(accountId)))
        .getSingleOrNull();
    if (account == null) return 0.0;
    // 跟寫入端(createInstallmentPlan)用同一個鍵值 fallback 規則:一般帳戶
    // 建立時一律會產生 syncId(LocalAccountRepository.createAccount),只有
    // 少數繞過那條路徑直接寫 DB 的情境(例如測試 fixture)才可能是 null,這
    // 裡跟寫入端保持對稱,不要求 syncId 一定存在。
    final key = account.syncId ?? accountId.toString();

    final plans = await (db.select(db.installmentPlans)
          ..where((t) => t.offsetBreakdownJson.isNotNull()))
        .get();
    var total = 0.0;
    for (final plan in plans) {
      final raw = plan.offsetBreakdownJson;
      if (raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final amount = decoded[key];
          if (amount is num) total += amount.toDouble();
        }
      } catch (_) {
        // 壞掉的 JSON(理論上不會發生,寫入端只會寫合法 JSON)不該讓整個
        // 帳單彙總查詢掛掉,跳過這一筆。
      }
    }
    return total;
  }

  @override
  Future<double> getCreditCardOffsetableBalance(int accountId) async {
    // 逐行對齐 credit_card_billing_providers.dart::_dueAsOf 的單一帳戶
    // (非群組)公式:charged 先扣掉之前所有沖銷,再扣 paidTotal,floor at 0。
    final charged = await _accountRepo.getCreditCardChargedAsOf(accountId);
    final offsetTotal = await getOffsetTotalForAccount(accountId);
    final paidTotal = await _accountRepo.getCreditCardPaidTotal(accountId);
    return creditCardDueAsOf(
      charged: charged - offsetTotal,
      paidTotal: paidTotal,
    );
  }

  // ============================================
  // 子專案 2:狀態變更操作。每個方法各自獨立照抄 Cloud
  // `installment_plans.py` 的邏輯,不共用計算 helper(見介面 docstring 的
  // 警告)。都在單一 db.transaction() 內完成,回傳的 [InstallmentChange]
  // 清單供 LocalRepository 包裝層拿去記 ChangeTracker。
  // ============================================

  @override
  Future<List<InstallmentChange>> updatePeriodOverride(
    int periodId, {
    double? amount,
    DateTime? dueAt,
    String? note,
  }) {
    return db.transaction(() async {
      final period = await (db.select(db.installmentPeriods)
            ..where((t) => t.id.equals(periodId)))
          .getSingleOrNull();
      if (period == null) {
        throw StateError('installment period not found: $periodId');
      }

      final now = DateTime.now();
      double? newTotal;
      double? newPrincipal;
      if (amount != null) {
        newTotal = amount;
        final computed = amount - period.interestAmount;
        newPrincipal = computed > 0 ? computed : 0.0;
      }

      await (db.update(db.installmentPeriods)
            ..where((t) => t.id.equals(periodId)))
          .write(InstallmentPeriodsCompanion(
        status: const d.Value(kInstallmentPeriodStatusOverridden),
        totalAmount:
            newTotal != null ? d.Value(newTotal) : const d.Value.absent(),
        principalAmount: newPrincipal != null
            ? d.Value(newPrincipal)
            : const d.Value.absent(),
        dueAt: dueAt != null ? d.Value(dueAt) : const d.Value.absent(),
        updatedAt: d.Value(now),
      ));

      final changes = <InstallmentChange>[];
      if (period.syncId != null) {
        changes.add(InstallmentChange(
          entityType: 'installment_period',
          entityId: period.id,
          entitySyncId: period.syncId!,
          ledgerId: period.ledgerId,
          action: 'update',
        ));
      }

      // 三個欄位互相獨立可選,只有真的帶了其中一個才動關聯交易。
      final hasTxUpdate = amount != null || dueAt != null || note != null;
      if (period.txId != null && hasTxUpdate) {
        final tx = await (db.select(db.transactions)
              ..where((t) => t.id.equals(period.txId!)))
            .getSingleOrNull();
        if (tx != null) {
          await (db.update(db.transactions)
                ..where((t) => t.id.equals(period.txId!)))
              .write(TransactionsCompanion(
            amount:
                newTotal != null ? d.Value(newTotal) : const d.Value.absent(),
            happenedAt: dueAt != null ? d.Value(dueAt) : const d.Value.absent(),
            note: note != null ? d.Value(note) : const d.Value.absent(),
          ));
          if (tx.syncId != null) {
            changes.add(InstallmentChange(
              entityType: 'transaction',
              entityId: tx.id,
              entitySyncId: tx.syncId!,
              ledgerId: tx.ledgerId,
              action: 'update',
            ));
          }
        }
      }

      return changes;
    });
  }

  @override
  Future<List<InstallmentChange>> rebalanceFrom(
    int planId,
    int periodNo, {
    required double interestRate,
    String? repaymentMethod,
  }) {
    return db.transaction(() async {
      final plan = await getInstallmentPlan(planId);
      if (plan == null) {
        throw StateError('installment plan not found: $planId');
      }
      final allPeriods = await getInstallmentPeriods(planId);
      final clickedPeriod = allPeriods.where((p) => p.periodNo == periodNo);
      if (clickedPeriod.isEmpty) {
        throw StateError('installment period not found: periodNo=$periodNo');
      }
      // 用使用者點的那個 periodNo 本身的 dueAt(不是下面 targets 過濾後清單
      // 的第一筆)——萬一 periodNo 本身剛好是 overridden,兩者會不一樣,要
      // 照抄 Cloud 用 clickedPeriod 這個。
      final clickedDueAt = clickedPeriod.first.dueAt;

      final targets = allPeriods
          .where((p) =>
              p.periodNo >= periodNo &&
              p.status != kInstallmentPeriodStatusOverridden)
          .toList();
      if (targets.isEmpty) {
        throw StateError('沒有可重算的期數');
      }

      double priorPrincipal = 0;
      double overriddenInRangePrincipal = 0;
      for (final p in allPeriods) {
        if (p.periodNo < periodNo) {
          priorPrincipal += p.principalAmount;
        } else if (p.status == kInstallmentPeriodStatusOverridden) {
          overriddenInRangePrincipal += p.principalAmount;
        }
      }
      final remainingPrincipal =
          plan.totalAmount - priorPrincipal - overriddenInRangePrincipal;
      if (remainingPrincipal <= 0) {
        throw StateError('沒有剩餘本金可重算');
      }

      final method = repaymentMethod ?? plan.repaymentMethod;
      final schedule = computeInstallmentPeriods(
        totalAmount: remainingPrincipal,
        periods: targets.length,
        firstPeriodAt: clickedDueAt,
        repaymentMethod: method,
        interestPeriod: plan.interestPeriod,
        interestRate: interestRate,
        roundAmounts: plan.roundAmounts,
        remainderPosition: plan.remainderPosition,
        gracePeriodMonths: 0, // 重算永遠不重新套寬限期
      );

      final now = DateTime.now();
      final changes = <InstallmentChange>[];
      for (var i = 0; i < targets.length; i++) {
        changes.addAll(await _applyComputedPeriod(
          targets[i],
          schedule[i],
          now: now,
        ));
      }

      await (db.update(db.installmentPlans)..where((t) => t.id.equals(planId)))
          .write(InstallmentPlansCompanion(
        interestRate: d.Value(interestRate),
        repaymentMethod: repaymentMethod != null
            ? d.Value(repaymentMethod)
            : const d.Value.absent(),
        updatedAt: d.Value(now),
      ));
      if (plan.syncId != null) {
        changes.add(InstallmentChange(
          entityType: 'installment_plan',
          entityId: plan.id,
          entitySyncId: plan.syncId!,
          ledgerId: plan.ledgerId,
          action: 'update',
        ));
      }

      return changes;
    });
  }

  @override
  Future<List<InstallmentChange>> earlyRepayPrincipal(
    int planId, {
    required double paymentAmount,
    int? accountId,
    DateTime? happenedAt,
  }) {
    return db.transaction(() async {
      final plan = await getInstallmentPlan(planId);
      if (plan == null) {
        throw StateError('installment plan not found: $planId');
      }
      final now = happenedAt ?? DateTime.now();
      final allPeriods = await getInstallmentPeriods(planId);

      double happenedPrincipal = 0;
      for (final p in allPeriods) {
        if (!p.dueAt.isAfter(now)) happenedPrincipal += p.principalAmount;
      }
      final futureTargets = allPeriods
          .where((p) =>
              p.dueAt.isAfter(now) &&
              p.status != kInstallmentPeriodStatusOverridden)
          .toList();
      double overriddenFuturePrincipal = 0;
      for (final p in allPeriods) {
        if (p.dueAt.isAfter(now) &&
            p.status == kInstallmentPeriodStatusOverridden) {
          overriddenFuturePrincipal += p.principalAmount;
        }
      }
      final distributableBefore =
          (plan.totalAmount - happenedPrincipal) - overriddenFuturePrincipal;
      final remainingAfter = _round2(distributableBefore - paymentAmount);
      if (remainingAfter < 0) {
        throw StateError('超過剩餘本金');
      }

      final changes = <InstallmentChange>[];
      final opNow = DateTime.now();

      // 建立部分還本交易。
      final repayTxId = await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: plan.ledgerId,
              type: 'expense',
              amount: paymentAmount,
              note: const d.Value('分期部分還本'),
              happenedAt: d.Value(now),
              categoryId: d.Value(plan.categoryId),
              accountId: d.Value(accountId ?? plan.accountId),
              syncId: d.Value(_uuid.v4()),
              installmentPlanSyncId: d.Value(plan.syncId),
            ),
          );
      final repayTx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(repayTxId)))
          .getSingle();
      if (repayTx.syncId != null) {
        changes.add(InstallmentChange(
          entityType: 'transaction',
          entityId: repayTxId,
          entitySyncId: repayTx.syncId!,
          ledgerId: plan.ledgerId,
          action: 'create',
        ));
      }

      if (remainingAfter <= 0.005 || futureTargets.isEmpty) {
        // 可分配的(未 overridden 的)本金已經還清——刪除這些期數。
        for (final entry in futureTargets) {
          changes.addAll(await _deletePeriodAndTx(entry));
        }
        // 只有連 overridden 的未來期數也沒有剩餘本金時,才算真的結清;
        // 使用者手動鎖定的 overridden 期數仍然代表真實欠款,不能被這次還本
        // 靜默抹掉,計畫維持 active、那些期數原樣保留。
        if (overriddenFuturePrincipal <= 0.005) {
          await (db.update(db.installmentPlans)
                ..where((t) => t.id.equals(planId)))
              .write(InstallmentPlansCompanion(
            status: const d.Value(kInstallmentPlanStatusSettled),
            updatedAt: d.Value(opNow),
          ));
          if (plan.syncId != null) {
            changes.add(InstallmentChange(
              entityType: 'installment_plan',
              entityId: plan.id,
              entitySyncId: plan.syncId!,
              ledgerId: plan.ledgerId,
              action: 'update',
            ));
          }
        }
      } else {
        final schedule = computeInstallmentPeriods(
          totalAmount: remainingAfter,
          periods: futureTargets.length,
          firstPeriodAt: futureTargets.first.dueAt,
          repaymentMethod: plan.repaymentMethod,
          interestPeriod: plan.interestPeriod,
          interestRate: plan.interestRate,
          roundAmounts: plan.roundAmounts,
          remainderPosition: plan.remainderPosition,
          gracePeriodMonths: 0,
        );
        for (var i = 0; i < futureTargets.length; i++) {
          changes.addAll(await _applyComputedPeriod(
            futureTargets[i],
            schedule[i],
            now: opNow,
          ));
        }
      }

      return changes;
    });
  }

  @override
  Future<List<InstallmentChange>> payoff(
    int planId, {
    int? accountId,
    DateTime? happenedAt,
  }) {
    return db.transaction(() async {
      final plan = await getInstallmentPlan(planId);
      if (plan == null) {
        throw StateError('installment plan not found: $planId');
      }
      final now = happenedAt ?? DateTime.now();
      final allPeriods = await getInstallmentPeriods(planId);

      double happenedPrincipal = 0;
      for (final p in allPeriods) {
        if (!p.dueAt.isAfter(now)) happenedPrincipal += p.principalAmount;
      }
      final remainingPrincipal = plan.totalAmount - happenedPrincipal;
      // 注意:這裡不排除 overridden——全部未到期期都會被刪,跟
      // rebalanceFrom/earlyRepayPrincipal 不同。
      final futurePeriods =
          allPeriods.where((p) => p.dueAt.isAfter(now)).toList();
      // 應計利息用「下一個尚未到期的那一期」原排程利息金額近似(提前結清時
      // 該期還沒真正發生,沒有更精細的按日計息基準可用——這是 Cloud 自己
      // 承認的設計妥協,不是 bug)。
      final accruedInterest =
          futurePeriods.isEmpty ? 0.0 : futurePeriods.first.interestAmount;
      final settleAmount = _round2(remainingPrincipal + accruedInterest);

      final changes = <InstallmentChange>[];
      final opNow = DateTime.now();

      if (settleAmount > 0) {
        final settleTxId = await db.into(db.transactions).insert(
              TransactionsCompanion.insert(
                ledgerId: plan.ledgerId,
                type: 'expense',
                amount: settleAmount,
                note: const d.Value('分期提前結清'),
                happenedAt: d.Value(now),
                categoryId: d.Value(plan.categoryId),
                accountId: d.Value(accountId ?? plan.accountId),
                syncId: d.Value(_uuid.v4()),
                installmentPlanSyncId: d.Value(plan.syncId),
              ),
            );
        final settleTx = await (db.select(db.transactions)
              ..where((t) => t.id.equals(settleTxId)))
            .getSingle();
        if (settleTx.syncId != null) {
          changes.add(InstallmentChange(
            entityType: 'transaction',
            entityId: settleTxId,
            entitySyncId: settleTx.syncId!,
            ledgerId: plan.ledgerId,
            action: 'create',
          ));
        }
      }

      for (final entry in futurePeriods) {
        changes.addAll(await _deletePeriodAndTx(entry));
      }

      await (db.update(db.installmentPlans)..where((t) => t.id.equals(planId)))
          .write(InstallmentPlansCompanion(
        status: const d.Value(kInstallmentPlanStatusSettled),
        updatedAt: d.Value(opNow),
      ));
      if (plan.syncId != null) {
        changes.add(InstallmentChange(
          entityType: 'installment_plan',
          entityId: plan.id,
          entitySyncId: plan.syncId!,
          ledgerId: plan.ledgerId,
          action: 'update',
        ));
      }

      return changes;
    });
  }

  @override
  Future<List<InstallmentChange>> terminateFutureInstallments(int planId) {
    return db.transaction(() async {
      final plan = await getInstallmentPlan(planId);
      if (plan == null) {
        throw StateError('installment plan not found: $planId');
      }
      final now = DateTime.now();
      final allPeriods = await getInstallmentPeriods(planId);
      final futurePeriods =
          allPeriods.where((p) => p.dueAt.isAfter(now)).toList();

      final changes = <InstallmentChange>[];
      for (final entry in futurePeriods) {
        changes.addAll(await _deletePeriodAndTx(entry));
      }

      await (db.update(db.installmentPlans)..where((t) => t.id.equals(planId)))
          .write(InstallmentPlansCompanion(
        status: const d.Value(kInstallmentPlanStatusTerminated),
        updatedAt: d.Value(now),
      ));
      if (plan.syncId != null) {
        changes.add(InstallmentChange(
          entityType: 'installment_plan',
          entityId: plan.id,
          entitySyncId: plan.syncId!,
          ledgerId: plan.ledgerId,
          action: 'update',
        ));
      }

      return changes;
    });
  }

  // ============================================
  // 子專案 3:退款。跟子專案 2 的 5 個狀態變更操作同款分工——不是
  // InstallmentRepository 介面方法的 override(介面簽名是 Future<void>),
  // 回傳 List<InstallmentChange> 供 LocalRepository 包裝層記 ChangeTracker
  // (見介面 docstring 的說明,理由同 §1 的「ChangeTracker 記錄方式」)。
  // ============================================

  @override
  Future<List<InstallmentChange>> refundPeriod(
    int planId,
    int txId, {
    double? amount,
    String? note,
    DateTime? happenedAt,
  }) {
    return db.transaction(() async {
      final plan = await getInstallmentPlan(planId);
      if (plan == null) {
        throw StateError('installment plan not found: $planId');
      }
      final allPeriods = await getInstallmentPeriods(planId);
      InstallmentPeriod? target;
      for (final p in allPeriods) {
        if (p.txId == txId) {
          target = p;
          break;
        }
      }
      if (target == null) {
        throw StateError('installment period not found for txId: $txId');
      }
      if (target.status == kInstallmentPeriodStatusRefunded) {
        throw StateError('installment period already refunded');
      }

      // 反查原交易只是為了拿它的 syncId 填 refundOfSyncId——不改動、不刪除
      // 這筆原交易本身(對齐 Cloud:「原交易不刪不改」)。理論上 period.txId
      // 一定指向一筆存在的交易,這裡的 getSingleOrNull 只是防禦性寫法。
      final originalTx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(txId)))
          .getSingleOrNull();

      final now = DateTime.now();
      final changes = <InstallmentChange>[];

      // 建立 1 筆 income 退款交易,沿用一般交易退款既有的 v34
      // refundOfSyncId 契約(同 TransactionEditUtils.refundTransaction/
      // entity_serializer.dart 的 refundOfId wire key)。**刻意不打
      // installmentPlanSyncId**——避免這筆退款交易本身被
      // InstallmentManagedTransactionException 擋住,讓使用者之後能透過
      // 一般刪除/編輯入口處理這筆退款記錄(對齐 Cloud
      // installment_plans.py:430-434 的原始註解)。
      final refundTxId = await db.into(db.transactions).insert(
            TransactionsCompanion.insert(
              ledgerId: plan.ledgerId,
              type: 'income',
              amount: amount ?? target.totalAmount,
              note: d.Value(note ?? '分期退款'),
              happenedAt: d.Value(happenedAt ?? now),
              accountId: d.Value(plan.accountId),
              refundOfSyncId: d.Value(originalTx?.syncId),
              syncId: d.Value(_uuid.v4()),
            ),
          );
      final refundTx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(refundTxId)))
          .getSingle();
      if (refundTx.syncId != null) {
        changes.add(InstallmentChange(
          entityType: 'transaction',
          entityId: refundTxId,
          entitySyncId: refundTx.syncId!,
          ledgerId: plan.ledgerId,
          action: 'create',
        ));
      }

      await (db.update(db.installmentPeriods)
            ..where((t) => t.id.equals(target!.id)))
          .write(InstallmentPeriodsCompanion(
        status: const d.Value(kInstallmentPeriodStatusRefunded),
        updatedAt: d.Value(now),
      ));
      if (target.syncId != null) {
        changes.add(InstallmentChange(
          entityType: 'installment_period',
          entityId: target.id,
          entitySyncId: target.syncId!,
          ledgerId: target.ledgerId,
          action: 'update',
        ));
      }

      return changes;
    });
  }

  // ============================================
  // 問題 A 修正(2026-09-03):單純刪除一期,不重算/不動其他期數金額。見
  // 介面 docstring。
  // ============================================

  @override
  Future<List<InstallmentChange>> deletePeriod(int planId, int periodId) {
    return db.transaction(() async {
      final plan = await getInstallmentPlan(planId);
      if (plan == null) {
        throw StateError('installment plan not found: $planId');
      }
      final period = await (db.select(db.installmentPeriods)
            ..where((t) => t.id.equals(periodId)))
          .getSingleOrNull();
      if (period == null) {
        throw StateError('installment period not found: $periodId');
      }
      if (period.planSyncId != plan.syncId) {
        throw StateError(
            'installment period $periodId does not belong to plan $planId');
      }

      final changes = <InstallmentChange>[];
      changes.addAll(await _deletePeriodAndTx(period));

      // 刪完這一期後,若計畫已經沒有任何期數,連帶刪掉計畫本身——避免留下
      // 0 期的空殼計畫。這不是財務操作(不重算/不標記 settled/terminated),
      // 純粹是刪除單期的自然收尾。
      final remaining = await getInstallmentPeriods(planId);
      if (remaining.isEmpty) {
        await (db.delete(db.installmentPlans)..where((t) => t.id.equals(planId)))
            .go();
        if (plan.syncId != null) {
          changes.add(InstallmentChange(
            entityType: 'installment_plan',
            entityId: plan.id,
            entitySyncId: plan.syncId!,
            ledgerId: plan.ledgerId,
            action: 'delete',
          ));
        }
      }

      return changes;
    });
  }

  /// 把 [computed](`computeInstallmentPeriods` 算出的單期結果)寫回
  /// [entry] 對應的 period + 交易,回傳異動清單。[rebalanceFrom]/
  /// [earlyRepayPrincipal] 的重算分支共用這個純粹的「寫入」步驟(不是
  /// 計算邏輯本身,不違反介面 docstring 的「不要合併成共用函式」警告——
  /// 那條警告針對的是可分配本金池/清零閾值等業務判斷,不是這種純 I/O)。
  Future<List<InstallmentChange>> _applyComputedPeriod(
    InstallmentPeriod entry,
    PeriodPlan computed, {
    required DateTime now,
  }) async {
    final changes = <InstallmentChange>[];
    await (db.update(db.installmentPeriods)
          ..where((t) => t.id.equals(entry.id)))
        .write(InstallmentPeriodsCompanion(
      principalAmount: d.Value(computed.principalAmount),
      interestAmount: d.Value(computed.interestAmount),
      totalAmount: d.Value(computed.totalAmount),
      updatedAt: d.Value(now),
    ));
    if (entry.syncId != null) {
      changes.add(InstallmentChange(
        entityType: 'installment_period',
        entityId: entry.id,
        entitySyncId: entry.syncId!,
        ledgerId: entry.ledgerId,
        action: 'update',
      ));
    }
    if (entry.txId != null) {
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(entry.txId!)))
          .getSingleOrNull();
      if (tx != null) {
        await (db.update(db.transactions)
              ..where((t) => t.id.equals(entry.txId!)))
            .write(TransactionsCompanion(
          amount: d.Value(computed.totalAmount),
        ));
        if (tx.syncId != null) {
          changes.add(InstallmentChange(
            entityType: 'transaction',
            entityId: tx.id,
            entitySyncId: tx.syncId!,
            ledgerId: tx.ledgerId,
            action: 'update',
          ));
        }
      }
    }
    return changes;
  }

  /// 刪除 [entry] 這期 + 其對應交易(若存在),回傳異動清單。
  /// [earlyRepayPrincipal]/[payoff]/[terminateFuture] 共用這個純粹的
  /// 「刪除」步驟——理由同 [_applyComputedPeriod]。
  Future<List<InstallmentChange>> _deletePeriodAndTx(
    InstallmentPeriod entry,
  ) async {
    final changes = <InstallmentChange>[];
    if (entry.txId != null) {
      final tx = await (db.select(db.transactions)
            ..where((t) => t.id.equals(entry.txId!)))
          .getSingleOrNull();
      if (tx != null) {
        await (db.delete(db.transactions)
              ..where((t) => t.id.equals(entry.txId!)))
            .go();
        if (tx.syncId != null) {
          changes.add(InstallmentChange(
            entityType: 'transaction',
            entityId: tx.id,
            entitySyncId: tx.syncId!,
            ledgerId: tx.ledgerId,
            action: 'delete',
          ));
        }
      }
    }
    await (db.delete(db.installmentPeriods)
          ..where((t) => t.id.equals(entry.id)))
        .go();
    if (entry.syncId != null) {
      changes.add(InstallmentChange(
        entityType: 'installment_period',
        entityId: entry.id,
        entitySyncId: entry.syncId!,
        ledgerId: entry.ledgerId,
        action: 'delete',
      ));
    }
    return changes;
  }
}

/// 對齐 Python `round(x, 2)` 的簡化版本(用 `toStringAsFixed` 再轉回
/// double)——跟 `installment_editor_page.dart` 年利率換算用的手法一致,
/// 避免二進位浮點誤差殘留。`earlyRepayPrincipal`/`payoff` 的金額判斷/結算
/// 都對齐 Cloud 用兩位小數四捨五入。
double _round2(double x) => double.parse(x.toStringAsFixed(2));
