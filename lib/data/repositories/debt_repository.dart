import '../db.dart';

/// 借還款方向：payable=我欠款,receivable=別人欠我(款項應收)。
/// 字面量對齐 BeeCount Cloud `schemas.py::DebtDirection`,改動需同步核對
/// server 端 `_LEDGER_MERGE_SPECS["debt"]`。
const String kDebtDirectionPayable = 'payable';
const String kDebtDirectionReceivable = 'receivable';

/// 借還款狀態,對齐 BeeCount Cloud `schemas.py::DebtStatus`。狀態不落地存,
/// 由 [DebtRepository] 在讀取時即時算(本金 - 已還款 vs closedAt),見
/// `list_debts` 的 derive 邏輯:
/// - closedAt 非 null → closed(優先於金額判斷,手動結案可以在未還清時發生)
/// - remaining <= 0.01 → settled
/// - repaid > 0 → partial
/// - 否則 → open
const String kDebtStatusOpen = 'open';
const String kDebtStatusPartial = 'partial';
const String kDebtStatusSettled = 'settled';
const String kDebtStatusClosed = 'closed';

/// 一筆欠款 + 即時算出的還款進度。[remainingAmount]/[status] 不對應 DB 欄位,
/// 每次查詢時用 principalAmount 減去 Transactions.debtSyncId 命中的還款交易
/// 加總得出 —— 跟 Cloud 的 read 路徑同一套語意,避免多寫入路徑各自維護衍生欄位。
class DebtWithStatus {
  final Debt debt;
  final double repaidAmount;
  final double remainingAmount;
  final String status;

  const DebtWithStatus({
    required this.debt,
    required this.repaidAmount,
    required this.remainingAmount,
    required this.status,
  });
}

/// 借還款仓库接口。ledger-scoped 实体(同 budget/ledger),对齐 BeeCount Cloud
/// 的 `debt` sync entity —— 完全比照其資料模型:
/// - principalAmount / direction 建立後不可修改(語意上等同刪除重建)
/// - 沒有獨立的「還款」實體,還款就是一筆帶 debtSyncId 的普通交易
/// - 有還款記錄的欠款不能刪除([deleteDebt] 應在呼叫端先檢查
///   [hasRepayments],repository 內部也會再擋一次)
abstract class DebtRepository {
  /// 建立欠款。[direction] 必須是 [kDebtDirectionPayable] 或
  /// [kDebtDirectionReceivable]。[originTransactionSyncId] 只給
  /// [createDebtWithOriginTransaction] 內部使用,直接呼叫這個方法的一般情境
  /// 不應該傳。
  Future<int> createDebt({
    required int ledgerId,
    required String direction,
    required String counterpartyName,
    required double principalAmount,
    DateTime? dueAt,
    String? note,
    int? categoryId,
    String? originTransactionSyncId,
    bool excludedFromTotal = false,
  });

  /// 從欠款分頁/欠款編輯頁「新增」時建立:同時建一筆一般交易(帳戶餘額
  /// 立即變動)+ 一筆 Debt 記錄,兩者之間**沒有任何 ID 關聯**(比照 BeeCount
  /// Cloud `debt_id === '__new__'` 的既有設計——起點交易不是還款,不能打
  /// debtSyncId,否則這筆欠款的 remainingAmount 會被自己的起點交易立刻沖抵
  /// 掉,見 `list_debts` 的 repaid 累加邏輯)。兩筆寫入包在同一個 db
  /// transaction 裡,避免交易建了但欠款沒建成的半殘狀態。
  ///
  /// [direction] 決定起點交易的 type:payable(我欠款,借到錢)→ income
  /// (帳戶餘額 +本金);receivable(款項應收,借出錢)→ expense(帳戶餘額
  /// -本金)。回傳新建 Debt 的本地 id。
  Future<int> createDebtWithOriginTransaction({
    required int ledgerId,
    required String direction,
    required String counterpartyName,
    required double principalAmount,
    required int accountId,
    DateTime? dueAt,
    String? note,
    int? categoryId,
    bool excludedFromTotal = false,
  });

  /// 更新可變欄位(counterpartyName / dueAt / note)。principalAmount /
  /// direction 不在這裡 —— 對齐 Cloud `WriteDebtUpdateRequest` 刻意不帶這兩個
  /// 欄位。[clearDueAt] / [clearNote] 顯式清空對應欄位(區分「沒傳」跟
  /// 「傳 null 清空」)。[excludedFromTotal] 為 null 代表不變更(這個欄位
  /// 只有 true/false 兩種有效值,不需要額外的 clear-flag)。
  Future<void> updateDebt(
    int id, {
    String? counterpartyName,
    DateTime? dueAt,
    bool clearDueAt = false,
    String? note,
    bool clearNote = false,
    int? categoryId,
    bool clearCategoryId = false,
    bool? excludedFromTotal,
  });

  /// 對象改名——同一帳本下所有 counterpartyName == oldName 的欠款一次改名
  /// (對齐 Moze「改名連動該對象所有記錄」)。回傳受影響的筆數。
  Future<int> renameCounterparty({
    required int ledgerId,
    required String oldName,
    required String newName,
  });

  /// 手動結案(closedAt = now)。結案不代表已還清,只是不再追蹤。
  Future<void> closeDebt(int id);

  /// 重新開啟(closedAt = null)。
  Future<void> reopenDebt(int id);

  /// 刪除欠款。若已有還款記錄(見 [hasRepayments])會拋出
  /// [StateError] —— 對齐 Cloud 的 `DEBT_HAS_REPAYMENTS` 守衛。
  Future<void> deleteDebt(int id);

  Future<Debt?> getDebt(int id);

  Future<Debt?> getDebtBySyncId(String syncId);

  /// 反查「這筆交易是不是某筆欠款的起點交易」——起點交易本身不帶
  /// [Transactions.debtSyncId](見 [createDebtWithOriginTransaction]),要透過
  /// 欠款側的 [Debts.originTransactionSyncId] 反查回來。
  Future<Debt?> getDebtByOriginTransactionSyncId(String syncId);

  /// 該欠款是否已有至少一筆還款交易掛著(debtId:delete 前置檢查)。
  Future<bool> hasRepayments(int debtId);

  /// 帳本下所有欠款(不含衍生狀態),依 dueAt 升冪排序(null 排最後)。
  Future<List<Debt>> getAllDebts(int ledgerId);

  /// 帳本下所有欠款 + 即時算出的還款進度/狀態。
  Future<List<DebtWithStatus>> getDebtsWithStatus(int ledgerId);

  Future<DebtWithStatus?> getDebtWithStatus(int id);

  /// 該欠款關聯的還款交易(依 happenedAt 由新到舊)。
  Future<List<Transaction>> getDebtRepaymentTransactions(int debtId);

  /// 帳本淨欠款餘額(Σreceivable 未結餘額 − Σpayable 未結餘額),供淨資產
  /// 統計使用。closed 但未還清的欠款不計入(已手動結案,視同不再追蹤)。
  Future<double> getNetDebtBalance(int ledgerId);

  /// 跨所有帳本的欠款,依帳本分組即時算出 receivable/payable 未結餘額。
  /// 供 [getNetWorthBreakdown]/[getNetWorthBreakdownByCurrency] 用——net worth
  /// 跨帳本聚合(accounts 是 user-global,不分帳本),欠款雖是 ledger-scoped
  /// 但同樣要納入全域淨資產,所以需要不按單一 ledgerId 過濾的版本。
  Future<List<({int ledgerId, double receivableRemaining, double payableRemaining})>>
      getDebtBalancesByLedgerForAllLedgers();

  /// 監聽帳本欠款列表變化。
  Stream<List<Debt>> watchDebts(int ledgerId);
}
