import '../../data/repositories/base_repository.dart';
import '../../utils/notification_factory.dart';
import 'logger_service.dart';

/// 專案預算超標本機推播(design doc 2026-09-06 §6.3)。走本機通知而非 Cloud
/// 通知中心——理由見該 spec §6.3:通知中心只對 BeeCount Cloud 使用者生效,
/// 其餘同步後端(iCloud/Supabase/WebDAV/S3)看不到,本機通知對所有後端一視
/// 同仁。通知文案沿用本檔案同層 [CreditCardReminderService] 的慣例,直接寫
/// 死中文,不走 l10n(這個 codebase 的本機推播目前都沒有走 l10n)。
class ProjectBudgetReminderService {
  /// 通知 ID = 3000 + projectId,同 [CreditCardReminderService] 的
  /// `2000 + accountId` 慣例,避開彼此的 id 區段。
  static int _notificationId(int projectId) => 3000 + projectId;

  /// 該筆交易寫入完成後呼叫(design doc §6.3「觸發點」):重新算這期用量,
  /// 超過門檻且這期還沒提醒過就跳本機通知。[projectSyncId] 為 null 或找不到
  /// 對應專案時直接返回(呼叫端不用先判斷)。
  static Future<void> checkAndNotify(
      BaseRepository repo, String? projectSyncId) async {
    if (projectSyncId == null) return;
    try {
      final project = await repo.getProjectBySyncId(projectSyncId);
      if (project == null) return;
      final threshold = project.reminderThresholdPercent;
      if (threshold == null) return;

      final usage = await repo.getProjectUsage(project, DateTime.now());
      final effectiveBudget = usage.effectiveBudget;
      if (effectiveBudget == null || effectiveBudget == 0) return;

      final rate = usage.used / effectiveBudget * 100;
      if (rate < threshold) return;

      final periodKey = usage.periodStart.toIso8601String();
      if (project.reminderNotifiedPeriodKey == periodKey) return;

      await NotificationFactory.getInstance().showNotification(
        id: _notificationId(project.id),
        title: '${project.name}预算提醒',
        body: '这期预算已使用 ${rate.toStringAsFixed(0)}%',
      );
      await repo.updateProjectReminderNotifiedKey(project.id, periodKey);
      logger.info('ProjectBudgetReminder',
          '已推播: projectId=${project.id} rate=${rate.toStringAsFixed(1)}%');
    } catch (e, stack) {
      logger.error('ProjectBudgetReminder', '推播检查失败', e, stack);
    }
  }
}
