import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/base_repository.dart';
import '../system/logger_service.dart';

/// SharedPreferences 旗標鍵——確保下面的一次性遷移只成功跑一次。
const String kProjectMigrationFlagKey = 'project_migration_v1_done';

/// 專案功能上線的一次性資料遷移(design doc §4)。
///
/// 把每個帳本既有的 `type='category'` 分類預算轉成專案,並回填該分類
/// **全部歷史**支出交易的 `projectSyncId`。`type='total'` 總預算不動
/// (design doc §0 決策 2——總支出＝帳本全部支出,獨立於專案標記之外)。
///
/// **冪等**:[kProjectMigrationFlagKey] 只在整個遷移成功跑完後才設 true。
/// 任何一步拋例外都不設旗標,下次啟動會整個重跑——重跑時已經轉走的分類
/// 預算不會重複轉,因為 [BudgetRepository.getCategoryBudgets] 只回傳「還
/// 沒被刪」的 `type='category'` 列(已刪的自然被排除)。
class ProjectMigrationService {
  final BaseRepository repo;

  /// 每批回填交易數,避免一次鎖住整個帳本的交易表(design doc §4)。
  static const int backfillBatchSize = 500;

  ProjectMigrationService(this.repo);

  Future<void> runIfNeeded({SharedPreferences? prefsOverride}) async {
    final prefs = prefsOverride ?? await SharedPreferences.getInstance();
    if (prefs.getBool(kProjectMigrationFlagKey) == true) return;

    try {
      final ledgers = await repo.getAllLedgers();
      for (final ledger in ledgers) {
        await _migrateLedger(ledger.id);
      }
      await prefs.setBool(kProjectMigrationFlagKey, true);
      logger.info(
          'ProjectMigration', '一次性遷移完成,共處理 ${ledgers.length} 個帳本');
    } catch (e, st) {
      // 任何異常都不該影響 app 啟動,也不設旗標——下次啟動重跑(同
      // main.dart::_runOrphanFileGcOnce 的慣例)。
      logger.warning('ProjectMigration', '遷移異常(下次启动重试): $e\n$st');
    }
  }

  Future<void> _migrateLedger(int ledgerId) async {
    // 注意:不能用 getCategoryBudgets——它只回傳 enabled=true 的列(給既有
    // 「分類預算」UI 用),已封存的分類預算會被漏掉。這裡要遷移全部,改用
    // getAllBudgets 自行篩 type='category'。
    final categoryBudgets = (await repo.getAllBudgets(ledgerId))
        .where((b) => b.type == 'category')
        .toList();
    var sortOrder = 0;
    for (final budget in categoryBudgets) {
      if (budget.categoryId == null) continue;
      final category = await repo.getCategoryById(budget.categoryId!);

      final projectId = await repo.createProject(
        ledgerId: ledgerId,
        name: category?.name ?? '未命名分類',
        icon: category?.icon,
        budgetAmount: budget.amount,
        periodType: 'monthly',
        visibleOnHome: false,
        sortOrder: sortOrder++,
      );
      if (!budget.enabled) {
        await repo.updateProject(projectId, enabled: false);
      }

      final project = await repo.getProject(projectId);
      final projectSyncId = project?.syncId;
      if (projectSyncId != null) {
        var affected = 0;
        do {
          affected = await repo.backfillProjectForCategoryBatch(
            ledgerId: ledgerId,
            categoryId: budget.categoryId!,
            projectSyncId: projectSyncId,
            limit: backfillBatchSize,
          );
        } while (affected > 0);
      }

      await repo.deleteBudget(budget.id);
      logger.info('ProjectMigration',
          '帳本 $ledgerId 分類預算(category=${budget.categoryId})已轉為專案 $projectId');
    }
  }
}
