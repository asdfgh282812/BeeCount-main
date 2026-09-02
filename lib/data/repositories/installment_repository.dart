import '../db.dart';

/// 分期計畫狀態,對齐 BeeCount Cloud `installment_plan.status`。
const String kInstallmentPlanStatusActive = 'active';
const String kInstallmentPlanStatusSettled = 'settled';
const String kInstallmentPlanStatusTerminated = 'terminated';

/// 分期期數狀態,對齐 BeeCount Cloud `installment_period.status`。
const String kInstallmentPeriodStatusGenerated = 'generated';
const String kInstallmentPeriodStatusOverridden = 'overridden';
const String kInstallmentPeriodStatusRefunded = 'refunded';

/// 一般刪除交易的入口(`LocalRepository.deleteTransaction`)偵測到目標交易
/// 屬於某個分期計畫時丟出這個例外——分期計畫生成/管理的交易不能透過一般
/// 刪除入口刪掉,必須改到分期管理頁操作對應的計畫級動作(單期覆寫/提前
/// 還本/提前結清/終止未來分期/整筆刪除計畫)。
///
/// 見 `docs/changes/2026-09-03-installment-tracking-phase2.md`「刪除攔截
/// 邊界」——這個檢查集中在 `LocalRepository.deleteTransaction` 這一個入口,
/// 取代子專案 1 只在 `transaction_detail_card.dart` 一處做檢查的暫時方案。
/// `LocalInstallmentRepository` 自己的狀態變更操作(`earlyRepayPrincipal`/
/// `payoff`/`terminateFuture`)刪除期數對應交易時直接對 Drift 表操作,不經過
/// `deleteTransaction`,不受這個攔截影響。
class InstallmentManagedTransactionException implements Exception {
  final int transactionId;
  final String planSyncId;

  const InstallmentManagedTransactionException(
      this.transactionId, this.planSyncId);

  @override
  String toString() =>
      'InstallmentManagedTransactionException(transactionId=$transactionId, '
      'planSyncId=$planSyncId)';
}

/// 子專案 2 狀態變更操作(`updatePeriodOverride`/`rebalanceFrom`/
/// `earlyRepayPrincipal`/`payoff`/`terminateFuture`)在單一 Drift transaction
/// 內產生的異動清單,供 [LocalRepository] 包裝層在操作完成後統一呼叫
/// ChangeTracker。
///
/// **為什麼不比照 `createInstallmentPlan`/`deleteInstallmentPlan` 那樣「操作
/// 前先查一次記下 syncId,操作後再逐一 record」**:這 5 個操作內部混合了
/// 刪除(`earlyRepayPrincipal`/`payoff`/`terminateFuture` 都會刪除部分
/// period/transaction)跟更新,刪除後那些列就查不到了,操作前一次性「記下
/// 全部可能受影響的列」跟操作內部真正判斷出的異動集合容易對不齊(例如
/// `earlyRepayPrincipal` 究竟是刪除分支還是重算分支,要等算出
/// `remainingAfter` 才知道)。改成由 repo 方法自己在執行當下,亲眼看着每一步
/// 操作直接記下「剛剛異動了什麼」,最不容易漏記或記錯。
///
/// **這個型別刻意不出現在 [InstallmentRepository] 抽象介面的方法簽名裡**
/// (介面上的 5 個狀態變更方法一律回傳 `Future<void>`)——`InstallmentChange`
/// 是「Drift 實作 → ChangeTracker 收尾」這條內部管線的搬運工具,只在
/// `LocalInstallmentRepository`(具體方法,不是 override)跟 `LocalRepository`
/// (呼叫端)之間傳遞,不該洩漏進公開介面型別。
class InstallmentChange {
  final String
      entityType; // 'installment_plan' | 'installment_period' | 'transaction'
  final int entityId;
  final String entitySyncId;
  final int ledgerId;
  final String action; // 'create' | 'update' | 'delete'

  const InstallmentChange({
    required this.entityType,
    required this.entityId,
    required this.entitySyncId,
    required this.ledgerId,
    required this.action,
  });
}

/// 一筆分期計畫 + 即時算出的進度(paidPeriods/nextPeriodAt/periodAmount)。
///
/// 這三個欄位**不對應 DB 欄位**,每次查詢時從 [InstallmentPeriods] 掃出來
/// (依 dueAt 排序),推導公式逐行對齐 BeeCount Cloud
/// `src/routers/read/ledgers.py::list_installment_plans`(line 1545-1620)——
/// 見 `LocalInstallmentRepository._withStatus` 的實作註解。
class InstallmentPlanWithStatus {
  final InstallmentPlan plan;
  final int paidPeriods;
  final DateTime nextPeriodAt;
  final double periodAmount;

  const InstallmentPlanWithStatus({
    required this.plan,
    required this.paidPeriods,
    required this.nextPeriodAt,
    required this.periodAmount,
  });
}

/// 分期付款仓库接口。ledger-scoped 实体(同 debt/budget),对齐 BeeCount
/// Cloud 的 `installment_plan`/`installment_period` sync entity。
///
/// **子專案 1 範圍**:只有建立/查詢/整筆刪除。狀態變更操作(單期覆寫、連同
/// 未來重算、部分提前還本、提前結清、終止未來分期——見設計文件 §3.2)是
/// 子專案 2 的範圍,這裡刻意不預先宣告那些方法簽名,留給子專案 2 再加。
abstract class InstallmentRepository {
  /// 建立分期計畫。單一 db transaction 內寫入 1 筆 [InstallmentPlans] + N 筆
  /// [Transactions](type=expense,`installmentPlanSyncId` 指回本計畫)+ N 筆
  /// [InstallmentPeriods](`status='generated'`,`txId` 反查對應交易)。
  ///
  /// 業務規則校驗(見設計文件 §1.4,不合法拋 [ArgumentError]):
  /// - [categoryId] 必填(Dart 簽名本身已強制非 null)。
  /// - `totalAmount > 0`、`1 <= periods <= 600`、`interestRate >= 0`、
  ///   `0 <= gracePeriodMonths < periods`。
  ///
  /// [accountId] 可以是合併帳單群組的子卡——`AccountCardPicker`(交易表單/
  /// 分期建立表單共用)本來就把群組主帳戶(`type == 'account_group'`)整個
  /// 過濾掉,子卡是唯一可選的信用卡帳戶,設計文件 §1.4 原本要求擋掉子卡、
  /// 改選群組主帳戶的校驗因此不可能被滿足,2026-09-03 移除(見
  /// `docs/changes/2026-09-03-installment-tracking-ux-fixes.md`)。
  ///
  /// 攤還排程由 `computeInstallmentPeriods`
  /// (`lib/services/installment/installment_amortization.dart`)算出,這裡
  /// 只負責落地寫入,不重複計息邏輯。回傳新建計畫的本地 id。
  ///
  /// **[offsetExistingBalance](子專案 4,信用卡帳單分期沖銷,對齐設計文件
  /// §3.4)**:把這張信用卡「既有的應繳欠款」轉成這筆分期計畫,而不是把它
  /// 當成一筆新的消費。啟用時:
  /// - [accountId] 必填,且必須是信用卡(不能是 `account_group`——目前 App
  ///   端只支援單一帳戶沖銷,合併帳單群組的沖銷分攤留待未來需要時再做,見
  ///   `docs/changes/2026-09-03-installment-tracking-phase4.md`)。
  /// - 該帳戶「目前應繳餘額」(對齐 `credit_card_billing_providers.dart`
  ///   的 `_dueAsOf` 口徑,已先扣掉先前其他分期計畫的沖銷)`<= 0.005` 視為
  ///   沒有欠款可沖銷,拋 [ArgumentError]。
  /// - [totalAmount] 不能超過那個應繳餘額(容許 0.01 的浮點誤差,對齐 Cloud
  ///   `total_amount > total_due + 0.01` 的判斷),超過拋 [ArgumentError]。
  /// - 沖銷的這部分**不產生任何交易**——跟一般分期一樣仍然會生成 N 筆
  ///   [Transactions]/[InstallmentPeriods](沖銷不影響這個既有流程),但額外
  ///   把 `{accountSyncId: totalAmount}` 寫進
  ///   [InstallmentPlans.offsetBreakdownJson],讓信用卡帳單彙總計算讀取後
  ///   從「應繳」金額裡扣掉,避免這筆既有欠款被沖銷後又被新產生的分期期數
  ///   交易重複算一次。
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
  });

  Future<InstallmentPlan?> getInstallmentPlan(int id);

  Future<InstallmentPlan?> getInstallmentPlanBySyncId(String syncId);

  /// 該計畫的全部期數,依 [InstallmentPeriod.periodNo] 排序。
  Future<List<InstallmentPeriod>> getInstallmentPeriods(int planId);

  /// 帳本下所有分期計畫 + 即時算出的進度,`active` 排前面(狀態相同時依
  /// [InstallmentPlan.firstPeriodAt] 由新到舊)。
  Future<List<InstallmentPlanWithStatus>> getInstallmentPlansWithStatus(
      int ledgerId);

  Future<InstallmentPlanWithStatus?> getInstallmentPlanWithStatus(int id);

  /// 整筆刪除計畫,連已發生期的交易也一併刪——對齐 Cloud `DELETE` 語意
  /// (避免刪計畫後 Transactions 頁還留一堆孤兒交易)。
  ///
  /// **這個「整筆刪除連交易一併刪」的行為刻意跟子專案 2 的
  /// `terminateFuture`(只刪未到期期,不動已發生期)不對稱**——不要為了
  /// 「一致性」把兩者改成同一套邏輯,這是設計文件 §3.1 明確要求保留的差異。
  Future<void> deleteInstallmentPlan(int id);

  /// 監聽帳本分期計畫列表變化(原始表,不含即時算出的進度)。
  Stream<List<InstallmentPlan>> watchInstallmentPlans(int ledgerId);

  /// 跨所有帳本,尚未到期的分期本金加總(「尚有未繳分期本金」),供帳戶
  /// 列表頁的虛擬入口卡片使用(角色同 [DebtRepository]
  /// `getDebtBalancesByLedgerForAllLedgers`,見 `_InstallmentEntryCard`)。
  Future<double> getOutstandingPrincipalAllLedgers();

  // ============================================
  // 子專案 4:信用卡帳單分期沖銷(見設計文件 §3.4)。
  // ============================================

  /// [accountId] 這張帳戶身上,累計被幾個分期計畫的 `offsetExistingBalance`
  /// 沖銷掉的既有欠款總額——掃描全部 [InstallmentPlans.offsetBreakdownJson]
  /// (依帳戶 [Accounts.syncId] 比對,沒有 `syncId` 時退化成比對本地 int id
  /// 字串,跟 `createInstallmentPlan` 寫入時的 fallback 規則對稱;不看
  /// status,任何狀態的計畫只要還沒被整筆刪除,沖銷就持續生效)。供
  /// `credit_card_billing_providers.dart` 的 `_dueAsOf` 從「應繳」金額裡扣
  /// 掉,避免重複計入。
  Future<double> getOffsetTotalForAccount(int accountId);

  /// [accountId] 這張信用卡「目前可沖銷的應繳餘額」——對齐
  /// `credit_card_billing_providers.dart::_dueAsOf` 的
  /// `charged - paidTotal`(floor at 0)公式,但 `charged` 已經先扣掉
  /// [getOffsetTotalForAccount],所以這裡回傳的已經是「扣掉之前所有沖銷之後
  /// 還剩下多少」,可以直接拿來當這次 `createInstallmentPlan(
  /// offsetExistingBalance: true)` 的 [totalAmount] 上限,也是
  /// `createInstallmentPlan` 自己驗證時用的同一個數字(唯一權威來源,UI 顯示
  /// 用的預覽值不會跟實際校驗對不上)。
  Future<double> getCreditCardOffsetableBalance(int accountId);

  // ============================================
  // 子專案 2:狀態變更操作(見設計文件 §3.2)。§0 核心不變量貫穿全部——
  // 重算「可分配本金池」時要先扣掉已過去期數的本金跟範圍內 overridden 期數
  // 的本金,重算結果只分配給範圍內非 overridden 的期數。這 5 個方法各自
  // 獨立照抄 Cloud 邏輯(`../BeeCount-Cloud/src/routers/write/
  // installment_plans.py`),刻意不合併成共用函式——`earlyRepayPrincipal`
  // 的清零閾值判斷 `<=0.005` 跟 `rebalanceFrom` 的 `<=0` 不完全一樣,「優化」
  // 成共用函式容易改壞其中一處的細節差異。
  // ============================================

  /// 單期覆寫(對齐 Cloud `installment_plans.py:305-382` PATCH period 端點)。
  /// 標記該期 `status='overridden'`(不再參與任何後續自動重算,也不能被
  /// 重算隱性挪用本金)。
  ///
  /// [amount]/[dueAt]/[note] 三者互相獨立可選:
  /// - 帶 [amount]:`totalAmount=amount`,`principalAmount=max(amount-
  ///   interestAmount, 0)`(**利息不變**——本金 = 新總額扣利息)。
  /// - 帶 [dueAt]:連動更新該期到期日。
  /// - 任一欄位非 null 時,同步更新關聯交易的對應欄位(amount/happenedAt/
  ///   note)。
  ///
  /// 找不到 [periodId] 時拋 [StateError]。
  Future<void> updatePeriodOverride(
    int periodId, {
    double? amount,
    DateTime? dueAt,
    String? note,
  });

  /// 連同未來重算(對齐 Cloud `installment_plans.py:464-573`)。從
  /// [periodNo] 開始,對範圍內未 `overridden` 的期數重新攤還——調利率、
  /// 可選換還款方式。
  ///
  /// 剩餘待攤還本金 = `plan.totalAmount - 已過去期數本金 - 範圍內 overridden
  /// 期數本金`(§0 核心不變量:overridden 期數金額是使用者手動鎖定的,不能被
  /// 重算隱性挪用其本金份額)。重算的 `firstPeriodAt` 用**使用者點的那個
  /// periodNo 本身的到期日**(不是過濾後 targets 清單的第一筆——萬一
  /// [periodNo] 本身剛好是 overridden,兩者會不一樣)。
  ///
  /// 找不到 [planId]/[periodNo]、範圍內沒有可重算的期數、或剩餘本金
  /// `<= 0` 時拋 [StateError]。
  Future<void> rebalanceFrom(
    int planId,
    int periodNo, {
    required double interestRate,
    String? repaymentMethod,
  });

  /// 部分提前還本(對齐 Cloud `installment_plans.py:575-717`)。建立 1 筆
  /// expense 交易(note="分期部分還本"),並對未到期、未 `overridden` 的期數
  /// 重新分配剩餘本金(或在還清時整批刪除)。
  ///
  /// 可分配本金池 = `(plan.totalAmount - 已過去期數本金) - 未到期
  /// overridden 期數本金`(§0 核心不變量)。`remainingAfter <= 0.005` 或已無
  /// 可重算的未來期時,刪除那些未到期、未 overridden 的期數 + 對應交易;
  /// 只有連未到期 overridden 期數的本金也 `<= 0.005` 時才真的把 plan 標
  /// `settled`(overridden 期數仍代表真實欠款,不能被靜默抹掉)。否則對剩餘
  /// 期數重新攤還。
  ///
  /// [paymentAmount] 超過可分配本金池時拋 [StateError]。[happenedAt]
  /// 預設 `DateTime.now()`。[accountId] 預設 `plan.accountId`。
  Future<void> earlyRepayPrincipal(
    int planId, {
    required double paymentAmount,
    int? accountId,
    DateTime? happenedAt,
  });

  /// 提前結清(對齐 Cloud `installment_plans.py:719-822`)。刪除**全部**未到
  /// 期期數(**不排除 overridden**——跟 [rebalanceFrom]/[earlyRepayPrincipal]
  /// 不同),視需要建立 1 筆結清交易(note="分期提前結清"),plan 標記
  /// `settled`。
  ///
  /// 結清金額 = 已過去期數以外的剩餘本金 + 應計利息(近似值:用「下一個
  /// 未到期期」原排程利息代替,不是精確按日計息——這是 Cloud 自己承認的
  /// 設計妥協,不是 bug)。金額 `<= 0` 時不建立交易(只刪期數+標記狀態)。
  ///
  /// [happenedAt] 預設 `DateTime.now()`。[accountId] 預設 `plan.accountId`。
  Future<void> payoff(
    int planId, {
    int? accountId,
    DateTime? happenedAt,
  });

  /// 終止未來分期(對齐 Cloud `installment_plans.py:824-885`)。刪除全部未到
  /// 期期數 + 對應交易,**不產生任何交易**,plan 標記 `terminated`。
  ///
  /// 命名刻意不叫 `terminateFuture`——`RecurringRuleRepository` 已經有一個
  /// 同名但簽名不同的方法(`terminateFuture(int ruleId)`,終止週期規則),
  /// 兩者都掛在 `BaseRepository` 上,同名會撞。
  Future<void> terminateFutureInstallments(int planId);

  // ============================================
  // 子專案 3:退款(見設計文件 §3.3)。
  // ============================================

  /// 單期退款(對齐 Cloud `installment_plans.py:385-462`)。找出
  /// [planId] 底下 `txId==[txId]` 的那一期,已經是 `refunded` 時拋
  /// [StateError]。建立 1 筆 income 交易,`refundOfSyncId` 指回 [txId] 對應
  /// 的原交易(沿用一般交易退款既有的 v34 `refundOfSyncId` 契約——見
  /// `TransactionEditUtils.refundTransaction`/`entity_serializer.dart` 的
  /// `refundOfId` wire key),`accountId` 用 `plan.accountId`。
  ///
  /// **刻意不打 `installmentPlanSyncId`**——這筆退款交易本身不是計畫管理的
  /// 一期,只是普通的退款引用,才不會被
  /// `InstallmentManagedTransactionException` 那層防呆誤判成分期交易而擋住
  /// 使用者之後想刪除/編輯這筆退款記錄(對齐 Cloud 該端點的原始註解)。
  ///
  /// [amount] 預設該期 `totalAmount`,可覆寫(天然支援部分退款);[note]
  /// 預設「分期退款」;[happenedAt] 預設 `DateTime.now()`。該期標記
  /// `status='refunded'`,原交易(`txId` 指向的那筆)不刪不改。
  ///
  /// **整筆退款不是這個方法的職責**——直接呼叫 [deleteInstallmentPlan]
  /// (連已發生期交易一起刪),兩者互斥,由呼叫端(UI)先讓使用者選擇要哪一種
  /// (見設計文件 §5.3 `InstallmentPeriodRefundChoiceDialog`)。
  Future<void> refundPeriod(
    int planId,
    int txId, {
    double? amount,
    String? note,
    DateTime? happenedAt,
  });

  // ============================================
  // 問題 A 修正(2026-09-03,見
  // docs/changes/2026-09-03-installment-tracking-delete-sync-fixes.md):
  // 交易明細頁「刪除」單筆分期交易時,不再硬擋去分期頁操作整個計畫,改成
  // 讓使用者選「只刪這一筆」還是「刪除整個計畫」。這個方法就是前者。
  // ============================================

  /// 單純刪除 [planId] 底下的一期 [periodId](+ 其對應交易,若存在)。
  ///
  /// **跟 [earlyRepayPrincipal]/[payoff]/[terminateFutureInstallments] 不
  /// 同**——這不是財務操作,不重算/不動用「可分配本金池」概念,也不影響其他
  /// 期數的 principal/interest。單純刪掉這一筆,對齐使用者「我就是要刪掉這
  /// 一期記錄」的直接意圖。
  ///
  /// 刪除後若這個計畫已經沒有任何期數,連帶刪除計畫本身(避免留下 0 期的
  /// 空殼計畫)——這是刪除單期的自然收尾,不是「提前結清」/「終止未來分期」
  /// 那種需要標記 `settled`/`terminated` 的語意。
  ///
  /// 找不到 [planId] 或 [periodId](或 [periodId] 不屬於 [planId])時拋
  /// [StateError]。
  Future<void> deletePeriod(int planId, int periodId);
}
