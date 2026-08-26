import '../db.dart';

/// 專案 repository 介面。ledger-scoped 实体(同 budget/debt/ledger),對齐
/// BeeCount Cloud 的 `project` sync entity —— 完整比照其資料模型
/// (§3.1 design doc):
/// - budgetAmount 可留空(純記錄型)
/// - periodType: monthly / yearly / fixed(fixed 才用 periodStart/End)
/// - carryoverEnabled 僅 monthly/yearly 有意義
/// - 沒有分類篩選/自動歸類規則(刻意排除,見 design doc §11)
abstract class ProjectRepository {
  /// 建立專案。[periodType] 必須是 'monthly'/'yearly'/'fixed'。
  Future<int> createProject({
    required int ledgerId,
    required String name,
    String? icon,
    double? budgetAmount,
    String periodType = 'monthly',
    DateTime? periodStart,
    DateTime? periodEnd,
    bool carryoverEnabled = false,
    bool visibleOnHome = true,
    int sortOrder = 0,
  });

  /// 更新可變欄位。[clearIcon]/[clearBudgetAmount]/[clearPeriodStart]/
  /// [clearPeriodEnd] 顯式清空對應欄位(區分「沒傳」跟「傳 null 清空」,
  /// 同 [DebtRepository.updateDebt] 的慣例)。
  Future<void> updateProject(
    int id, {
    String? name,
    String? icon,
    bool clearIcon = false,
    double? budgetAmount,
    bool clearBudgetAmount = false,
    String? periodType,
    DateTime? periodStart,
    bool clearPeriodStart = false,
    DateTime? periodEnd,
    bool clearPeriodEnd = false,
    bool? carryoverEnabled,
    bool? visibleOnHome,
    bool? enabled,
    int? sortOrder,
  });

  /// 刪除規則對齐 server(design doc §7/§8):該專案若有任何交易關聯(見
  /// [hasTransactions])→ 只設 `enabled=false`(封存),不刪列;沒有 →
  /// 直接刪除整列。呼叫端(未來 UI)應先呼叫 [hasTransactions] 決定要顯示
  /// 「刪除」還是「封存」提示,但本方法本身也會套用同樣規則,不依賴呼叫端
  /// 守規矩。
  Future<void> deleteProject(int id);

  Future<Project?> getProject(int id);

  Future<Project?> getProjectBySyncId(String syncId);

  /// 帳本下所有專案,依 [sortOrder] 升冪排序。[includeDisabled] 為 false
  /// 時只回傳 `enabled=true` 的(預設列表視圖用);true 時含已封存的(「顯示
  /// 已封存」篩選用)。
  Future<List<Project>> getAllProjects(int ledgerId,
      {bool includeDisabled = false});

  Stream<List<Project>> watchProjects(int ledgerId,
      {bool includeDisabled = false});

  /// 該專案是否有交易關聯(刪除前置檢查,同
  /// [DebtRepository.hasRepayments])。[projectSyncId] 是
  /// [Transactions.projectSyncId] 命中的那個字串。命名刻意加 `project`
  /// 前綴,避免跟 [AccountRepository.hasTransactions](參數是 accountId)
  /// 在 [BaseRepository] 組合時撞名。
  Future<bool> projectHasTransactions(String projectSyncId);
}
