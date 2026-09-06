import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../data/repositories/project_repository.dart';
import '../providers.dart';
import '../utils/month_range.dart';

/// 專案刷新觸發器(同 [budgetRefreshProvider] 慣例——建立/編輯/刪除後 bump
/// 一次強制下游 FutureProvider 重新拉取)。
final projectRefreshProvider = StateProvider<int>((ref) => 0);

/// 當前帳本下所有啟用中的專案 + 花費統計,依 sortOrder 排序。
final projectUsagesProvider =
    FutureProvider<List<ProjectWithUsage>>((ref) async {
  ref.watch(projectRefreshProvider);

  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  return repo.getAllProjectUsages(ledgerId, DateTime.now());
});

/// 含已封存專案的完整清單(「顯示已封存」篩選開啟時用)。
final allProjectUsagesIncludingDisabledProvider =
    FutureProvider<List<ProjectWithUsage>>((ref) async {
  ref.watch(projectRefreshProvider);

  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  return repo.getAllProjectUsages(ledgerId, DateTime.now(),
      includeDisabled: true);
});

/// 單一專案 + 花費統計(詳情頁用)。
final projectUsageProvider =
    FutureProvider.family<ProjectWithUsage?, int>((ref, projectId) async {
  ref.watch(projectRefreshProvider);

  final repo = ref.watch(repositoryProvider);
  final project = await repo.getProject(projectId);
  if (project == null) return null;

  final usage = await repo.getProjectUsage(project, DateTime.now());
  return ProjectWithUsage(project: project, usage: usage);
});

/// 監聽當前帳本的專案原始列表(不含花費統計,用於選擇器等輕量場景)。
final projectsStreamProvider = StreamProvider<List<Project>>((ref) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);

  return repo.watchProjects(ledgerId);
});

/// 專案詳情頁的期間切換 offset 狀態。key=projectId,value=往回第幾期
/// (0=當期,1=上一期...)。
class ProjectPeriodOffsetNotifier extends StateNotifier<Map<int, int>> {
  ProjectPeriodOffsetNotifier() : super({});

  void setOffset(int projectId, int offset) =>
      state = {...state, projectId: offset};
}

final projectPeriodOffsetProvider =
    StateNotifierProvider<ProjectPeriodOffsetNotifier, Map<int, int>>(
        (ref) => ProjectPeriodOffsetNotifier());

/// [project] 在 [periodType] 對應的 offset 錨點。用 label 手法(day=1 的
/// DateTime)而非直接對 `now` 做 `month - offset`,避免月底日期在短月份滾動
/// 進位的邊界 bug(同 [_previousPeriodRange] 已驗證過的手法,見
/// local_project_repository.dart)。`fixed` 週期 offset 恆為 0,anchor 用
/// 什麼日期都不影響(getProjectUsage 對 fixed 直接讀 project 自帶的
/// periodStart/periodEnd)。
DateTime _projectPeriodAnchor(Project project, int offset, int monthStartDay) {
  final now = DateTime.now();
  switch (project.periodType) {
    case 'yearly':
      // 固定用年中日期,年份加減沒有「月底進位」這種邊界問題。
      return DateTime(now.year - offset, 7, 1);
    case 'fixed':
      return now;
    case 'monthly':
    default:
      final currentLabel = labelForDate(now, monthStartDay);
      final targetLabel =
          DateTime(currentLabel.year, currentLabel.month - offset, 1);
      return periodForLabel(targetLabel.year, targetLabel.month, monthStartDay)
          .start;
  }
}

/// 專案詳情頁聚合資料:專案本身、選定期間的用量、分類拆解、分類子預算分配、
/// 全部一級分類(供 UI 合併 icon/名稱)、目前的 offset。
class ProjectDetailData {
  final Project project;
  final ProjectUsage usage;
  final List<ProjectCategoryUsage> breakdown;
  final List<ProjectCategoryBudget> categoryBudgets;
  final List<Category> allCategories;
  final int offset;

  const ProjectDetailData({
    required this.project,
    required this.usage,
    required this.breakdown,
    required this.categoryBudgets,
    required this.allCategories,
    required this.offset,
  });
}

/// 專案詳情頁用:依 [projectPeriodOffsetProvider] 選定的期間,組合出用量 +
/// 分類拆解 + 分類子預算分配的完整資料。取代舊的 `projectUsageProvider` 固定
/// `DateTime.now()` 的做法(該 provider 保留供其它仍只需要「當期」的呼叫端
/// 使用,不刪除)。
final projectDetailDataProvider =
    FutureProvider.family<ProjectDetailData?, int>((ref, projectId) async {
  ref.watch(projectRefreshProvider);

  final offset = ref.watch(projectPeriodOffsetProvider)[projectId] ?? 0;
  final repo = ref.watch(repositoryProvider);

  final project = await repo.getProject(projectId);
  if (project == null) return null;

  final ledger = ref.watch(currentLedgerProvider).value;
  final monthStartDay = ledger?.monthStartDay ?? 1;
  final effectiveOffset = project.periodType == 'fixed' ? 0 : offset;
  final anchor = _projectPeriodAnchor(project, effectiveOffset, monthStartDay);

  final usage = await repo.getProjectUsage(project, anchor);

  final syncId = project.syncId;
  final breakdown = syncId == null
      ? <ProjectCategoryUsage>[]
      : await repo.getProjectCategoryBreakdown(
          syncId,
          start: usage.periodStart,
          end: usage.periodEnd,
        );

  final categoryBudgets = await repo.getProjectCategoryBudgets(project.id);
  final allCategories = await repo.getAllCategories();

  return ProjectDetailData(
    project: project,
    usage: usage,
    breakdown: breakdown,
    categoryBudgets: categoryBudgets,
    allCategories: allCategories,
    offset: effectiveOffset,
  );
});
