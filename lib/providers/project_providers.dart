import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../data/repositories/project_repository.dart';
import '../providers.dart';

/// 專案刷新觸發器(同 [budgetRefreshProvider] 慣例——建立/編輯/刪除後 bump
/// 一次強制下游 FutureProvider 重新拉取)。
final projectRefreshProvider = StateProvider<int>((ref) => 0);

/// 當前帳本下所有啟用中的專案 + 花費統計,依 sortOrder 排序。
final projectUsagesProvider = FutureProvider<List<ProjectWithUsage>>((ref) async {
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
