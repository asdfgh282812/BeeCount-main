import '../db.dart';

/// 專案在某個週期內的花費/預算/結餘。跟 [BudgetUsage] 的差異:[budget] 可為
/// null(純記錄型專案,design doc §3.1),[carriedOver] 是 carryoverEnabled 時
/// 從上一週期帶入的結餘(可能為負,代表上期超支)。
class ProjectUsage {
  final double used;
  final double? budget;
  final double? carriedOver;

  /// 該期實際併入預算的收入總額(project.incomeIncludedInBudget=true 時才
  /// 非 null),UI 顯示明細/除錯用,不是 [effectiveBudget] 之外的必要欄位。
  final double? incomeIncluded;

  /// 本次計算採用的週期範圍,半開區間 [periodStart, periodEnd)。UI 顯示週期
  /// 文字(本月/年度/起訖日)用。
  final DateTime periodStart;
  final DateTime periodEnd;

  const ProjectUsage({
    required this.used,
    this.budget,
    this.carriedOver,
    this.incomeIncluded,
    required this.periodStart,
    required this.periodEnd,
  });

  /// 有效預算 = budget + carriedOver(carryoverEnabled 時) +
  /// incomeIncluded(incomeIncludedInBudget 時);純記錄專案為 null。
  double? get effectiveBudget => budget == null
      ? null
      : budget! + (carriedOver ?? 0) + (incomeIncluded ?? 0);

  double? get remaining =>
      effectiveBudget == null ? null : effectiveBudget! - used;

  /// 使用率(0-1+,可超過 1 代表超支);純記錄或 effectiveBudget==0 時為 null
  /// (UI 應顯示「純記錄」而非進度條)。
  double? get rate {
    final b = effectiveBudget;
    if (b == null || b == 0) return null;
    return (used / b).clamp(0.0, double.infinity);
  }
}

/// 專案 + 其花費統計,列表/總覽頁用(同 [CategoryBudgetUsage] 帶完整實體的慣例)。
class ProjectWithUsage {
  final Project project;
  final ProjectUsage usage;

  const ProjectWithUsage({required this.project, required this.usage});
}

/// 該專案在某期間內,依一級分類分組的花費/收入統計 + 筆數。跟
/// [ProjectCategoryBudgets] 的分配額度是兩個獨立來源,由呼叫端合併成「已
/// 分配/未分配/未設定」三組(分組是展示邏輯,不在 repository 層做)。
class ProjectCategoryUsage {
  final int? categoryId;
  final double expenseTotal;
  final double incomeTotal;
  final int recordCount;

  const ProjectCategoryUsage({
    required this.categoryId,
    required this.expenseTotal,
    required this.incomeTotal,
    required this.recordCount,
  });
}

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
    bool incomeIncludedInBudget = false,
    bool dailyBudgetEnabled = false,
    String dailyBudgetMode = 'proportional',
    int? reminderThresholdPercent,
  });

  /// 更新可變欄位。[clearIcon]/[clearBudgetAmount]/[clearPeriodStart]/
  /// [clearPeriodEnd]/[clearReminderThresholdPercent] 顯式清空對應欄位(區分
  /// 「沒傳」跟「傳 null 清空」,同 [DebtRepository.updateDebt] 的慣例)。
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
    bool? incomeIncludedInBudget,
    bool? dailyBudgetEnabled,
    String? dailyBudgetMode,
    int? reminderThresholdPercent,
    bool clearReminderThresholdPercent = false,
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

  /// [project] 在 [now] 所屬週期的花費/預算統計。週期依 [Project.periodType]:
  /// - `monthly`:跟隨帳本 `monthStartDay`(同 [BudgetRepository.getBudgetUsage]
  ///   口徑)。
  /// - `yearly`:自然年 1/1 ~ 次年 1/1(不跟隨 monthStartDay——設計文件未特別
  ///   要求,取最簡單直覺的定義)。
  /// - `fixed`:專案自帶的 `periodStart`/`periodEnd`(含當天,內部轉半開區間)。
  ///
  /// `carryoverEnabled` 時會多查一次「上一週期」的花費算出結轉金額,只算前一
  /// 期一次,不做多期遞迴結轉;`fixed` 週期沒有「上一期」概念,即使
  /// `carryoverEnabled=true` 也不生效(UI 應停用該開關,見 design doc §8)。
  Future<ProjectUsage> getProjectUsage(Project project, DateTime now);

  /// 帳本下所有(依 [includeDisabled])專案的花費統計,依 [sortOrder] 排序。
  Future<List<ProjectWithUsage>> getAllProjectUsages(int ledgerId, DateTime now,
      {bool includeDisabled = false});

  /// 建立/更新一筆分類子預算分配(依 (projectId, categoryId) 唯一鍵
  /// upsert)。[categoryId] 應為一級分類,呼叫端(UI 分類選擇器)負責守規矩,
  /// repository 層不額外驗證(同全庫對 level 的處理慣例)。
  Future<int> upsertProjectCategoryBudget({
    required int projectId,
    required int categoryId,
    required String mode,
    double? fixedAmount,
    double? percentage,
    bool carryoverEnabled = false,
  });

  /// 移除一筆分類子預算分配(分類本身被刪除,或使用者手動移除分配時呼叫,
  /// 直接刪列,無軟刪除必要)。
  Future<void> removeProjectCategoryBudget(int projectId, int categoryId);

  Future<List<ProjectCategoryBudget>> getProjectCategoryBudgets(int projectId);

  /// 該專案在 [start, end) 期間內,依一級分類分組的支出/收入統計 + 筆數。
  /// 回傳所有「在期間內有交易」的分類;沒有交易的分類由呼叫端自行從
  /// [getAllProjects]/`getAllCategories()` 補上「未設定預算」那組。
  Future<List<ProjectCategoryUsage>> getProjectCategoryBreakdown(
    String projectSyncId, {
    required DateTime start,
    required DateTime end,
  });

  /// 純本機欄位寫入(§6.3 預算提醒):記錄「這期已經提醒過」,不經過
  /// [ChangeTracker](這欄位本來就不同步)。
  Future<void> updateProjectReminderNotifiedKey(int id, String periodKey);
}
