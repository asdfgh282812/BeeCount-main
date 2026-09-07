import '../services/system/logger_service.dart';
import '../utils/notification_factory.dart';

/// ②帳單結算提醒 notification id 基底,`id = kBillingReminderIdBase + accountId`。
const int kBillingReminderIdBase = 3000000;

/// ③到期連續提醒 notification id 基底,
/// `id = kDueReminderIdBase + accountId * 100 + dayOffset`。乘數用 100(而不是
/// 更小的 10)、跟 ②基底相隔一百萬,是為了在 accountId 落在合理範圍(不到一萬
/// 張帳戶)內, ②③彼此的 id 不會互相落進對方的區間——self-review 階段發現
/// `*1000` 搭配較小基底時,特定 accountId 組合會真的撞號,見設計文件
/// `docs/superpowers/specs/2026-09-07-credit-card-notifications-badge-fix-design.md`
/// 「id 範圍設計說明」一節。
const int kDueReminderIdBase = 4000000;

/// ③ dayOffset 的絕對安全上限——遠超 UI 開放的最大天數(見
/// `credit_card_reminder_overview_page.dart` 的 `[3,5,7,10]` 天選項),只用來
/// 在使用者「關閉開關」或「調低天數」時,掃描要不要取消超出新範圍的殘留排程。
const int kDueReminderMaxDayOffsetCap = 99;

/// 給定 [dueDate]/[maxDays]/[hour]/[minute]/[now],算出③到期連續提醒「還需要
/// 排程」的 (dayOffset, scheduledDate) 清單——排程時間已經早於 [now] 的天數會
/// 被跳過(不補發,避免用一個過去的時間點觸發本地通知立即彈出),讓「最多連續
/// N 天」的視窗自然收斂。抽成純函式方便單元測試,不需要碰
/// `NotificationFactory`(這個工廠在非 Android/iOS 的測試環境會直接拋
/// `UnsupportedError`)。
List<({int dayOffset, DateTime scheduledDate})> dueReminderScheduleSlots({
  required DateTime dueDate,
  required int maxDays,
  required DateTime now,
  int hour = 10,
  int minute = 0,
}) {
  final slots = <({int dayOffset, DateTime scheduledDate})>[];
  for (var offset = 0; offset < maxDays; offset++) {
    final day = dueDate.add(Duration(days: offset));
    final scheduledDate = DateTime(day.year, day.month, day.day, hour, minute);
    if (scheduledDate.isAfter(now)) {
      slots.add((dayOffset: offset, scheduledDate: scheduledDate));
    }
  }
  return slots;
}

/// 信用卡还款提醒服务
///
/// 三种通知各自的 notification id:①提前提醒(既有,不变)`2000 + accountId`;
/// ②帳單結算提醒 [kBillingReminderIdBase] + accountId;③到期連續提醒
/// [kDueReminderIdBase] + accountId * 100 + dayOffset。
///
/// 三种通知的「是否啟用/天數/提醒時間」是全域設定(不分卡,2026-09-07 範圍
/// 調整——使用者反饋不想逐卡設定),但排程本身仍是逐卡各自呼叫(每張卡各自的
/// notification id、各自的 remainingDue/dueDate)。本类刻意不依赖 Riverpod/
/// repo/SharedPreferences——是否要发送、发送时用的 remainingDue/dueDate/
/// enabled/天數,一律由「有 repo 的调用端」
/// (`credit_card_reminder_reevaluation.dart` 的
/// `reevaluateAllCreditCardReminders`)算好以参数传入,详见该文件的 docstring。
class CreditCardReminderService {
  /// ②帳單結算提醒的 notification id。
  static int billingReminderId(int accountId) =>
      kBillingReminderIdBase + accountId;

  /// ③到期連續提醒第 [dayOffset] 天的 notification id。
  static int dueReminderId(int accountId, int dayOffset) =>
      kDueReminderIdBase + accountId * 100 + dayOffset;

  /// 计算下一次提醒时间
  static DateTime _nextReminderDate({
    required int paymentDueDay,
    required int daysBefore,
    int hour = 10,
    int minute = 0,
  }) {
    final now = DateTime.now();
    final reminderDay = paymentDueDay - daysBefore;

    // 本月提醒日
    var reminderDate = DateTime(now.year, now.month, reminderDay, hour, minute);

    // 如果 reminderDay <= 0，回到上月
    if (reminderDay <= 0) {
      final prevMonth = DateTime(now.year, now.month - 1, 1);
      final daysInPrevMonth =
          DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
      reminderDate = DateTime(
        prevMonth.year,
        prevMonth.month,
        daysInPrevMonth + reminderDay,
        hour,
        minute,
      );
    }

    // 如果已经过了本月提醒日，安排下月
    if (reminderDate.isBefore(now)) {
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      final nextReminderDay = paymentDueDay - daysBefore;
      if (nextReminderDay > 0) {
        reminderDate = DateTime(
            nextMonth.year, nextMonth.month, nextReminderDay, hour, minute);
      } else {
        // 跨月情况
        final daysInNextMonth =
            DateTime(nextMonth.year, nextMonth.month + 1, 0).day;
        reminderDate = DateTime(
          nextMonth.year,
          nextMonth.month,
          (daysInNextMonth + nextReminderDay).clamp(1, daysInNextMonth),
          hour,
          minute,
        );
      }
    }

    return reminderDate;
  }

  /// 调度还款提醒
  ///
  /// [skipIfCloudActive]：BeeCount Cloud 后端已激活时传 true —— Cloud 端
  /// 每 15 分钟跑一次 `card_due` cron,会把同样的提醒写进通知中心
  /// (见 `lib/pages/notifications/notification_center_page.dart`),本地
  /// 再排一次 OS 通知会重复提醒用户,故直接取消本地排程,交给 Cloud。
  /// 调用方(`credit_card_reminder_reevaluation.dart` / main.dart)负责算这个
  /// bool,本类本身不依赖 Riverpod。
  static Future<void> scheduleReminder({
    required int accountId,
    required String accountName,
    required int paymentDueDay,
    required int daysBefore,
    int hour = 10,
    int minute = 0,
    bool skipIfCloudActive = false,
  }) async {
    if (skipIfCloudActive) {
      await cancelReminder(accountId);
      return;
    }
    try {
      final notificationUtil = NotificationFactory.getInstance();
      final notificationId = 2000 + accountId;
      final scheduledDate = _nextReminderDate(
        paymentDueDay: paymentDueDay,
        daysBefore: daysBefore,
        hour: hour,
        minute: minute,
      );

      await notificationUtil.scheduleOnceReminder(
        id: notificationId,
        title: '$accountName還款日即將到來',
        body: '還款日為每月$paymentDueDay日，請及時還款',
        scheduledDate: scheduledDate,
      );

      logger.info('CreditCardReminder',
          '已调度提醒: accountId=$accountId, 时间=$scheduledDate');
    } catch (e, stack) {
      logger.error('CreditCardReminder', '调度提醒失败', e, stack);
    }
  }

  /// 取消还款提醒
  static Future<void> cancelReminder(int accountId) async {
    try {
      final notificationUtil = NotificationFactory.getInstance();
      final notificationId = 2000 + accountId;
      await notificationUtil.cancelNotification(notificationId);
      logger.info('CreditCardReminder', '已取消提醒: accountId=$accountId');
    } catch (e, stack) {
      logger.error('CreditCardReminder', '取消提醒失败', e, stack);
    }
  }

  /// 調度②帳單結算提醒(每月 `billingDay` 當天單次)。[remainingDue]/
  /// [billingDate] 由呼叫端算好傳入(見本類別開頭 docstring)——
  /// [billingDate] 是本期結帳日(`billingCyclePeriod(billingDay, 0).end`),
  /// [remainingDue] 是以該結帳日為 cutoff 算出的應繳金額快照,`null` 或
  /// `<= 0.01`(當期無應繳金額)一律視為不發送、取消殘留排程。
  ///
  /// 排程時間若已經早於現在(例如今天已過了 [hour]:[minute]、或呼叫端傳入
  /// 的 [billingDate] 已經是過去),這個月的結算提醒就不補發——沿用③的
  /// 「錯過就不補、下一輪重新評估自然對齊」原則,不新增背景任務去追。
  static Future<void> scheduleBillingReminder({
    required int accountId,
    required String accountName,
    required DateTime billingDate,
    required double? remainingDue,
    required String currencyCode,
    int hour = 10,
    int minute = 0,
  }) async {
    if (remainingDue == null || remainingDue <= 0.01) {
      await cancelBillingReminder(accountId);
      return;
    }
    final scheduledDate = DateTime(
        billingDate.year, billingDate.month, billingDate.day, hour, minute);
    if (!scheduledDate.isAfter(DateTime.now())) {
      await cancelBillingReminder(accountId);
      return;
    }
    try {
      final notificationUtil = NotificationFactory.getInstance();
      await notificationUtil.scheduleOnceReminder(
        id: billingReminderId(accountId),
        title: '帳單結算提醒',
        body: '✓ [${billingDate.month}月] $accountName結算明細已出爐，應繳 '
            '${remainingDue.toStringAsFixed(2)} $currencyCode',
        scheduledDate: scheduledDate,
      );
      logger.info('CreditCardReminder',
          '已调度帳單結算提醒: accountId=$accountId, 时间=$scheduledDate');
    } catch (e, stack) {
      logger.error('CreditCardReminder', '调度帳單結算提醒失败', e, stack);
    }
  }

  /// 取消②帳單結算提醒。
  static Future<void> cancelBillingReminder(int accountId) async {
    try {
      final notificationUtil = NotificationFactory.getInstance();
      await notificationUtil.cancelNotification(billingReminderId(accountId));
    } catch (e, stack) {
      logger.error('CreditCardReminder', '取消帳單結算提醒失败', e, stack);
    }
  }

  /// 調度③到期連續提醒:一次性預先排好 [dueDate] ~ [dueDate] + ([maxDays] - 1)
  /// 天,各自獨立的一次性通知(見 [dueReminderScheduleSlots] 的排程時間計算)。
  /// [remainingDue]/[dueDate] 由呼叫端算好傳入——`null`(已繳清或當期無應繳
  /// 金額)一律取消所有殘留排程;非 `null` 時,超出 [maxDays] 的殘留排程
  /// (例如使用者把天數從 10 調低到 3)也會一併取消。
  static Future<void> scheduleDueReminders({
    required int accountId,
    required String accountName,
    required int maxDays,
    required double? remainingDue,
    required DateTime? dueDate,
    required String currencyCode,
    int hour = 10,
    int minute = 0,
  }) async {
    if (remainingDue == null || remainingDue <= 0.01 || dueDate == null) {
      await cancelDueReminders(accountId);
      return;
    }
    try {
      final notificationUtil = NotificationFactory.getInstance();
      final slots = dueReminderScheduleSlots(
        dueDate: dueDate,
        maxDays: maxDays,
        now: DateTime.now(),
        hour: hour,
        minute: minute,
      );
      final amountText = remainingDue.toStringAsFixed(2);
      for (final slot in slots) {
        final title =
            slot.dayOffset == 0 ? '$accountName繳款日到了' : '$accountName繳款已逾期';
        await notificationUtil.scheduleOnceReminder(
          id: dueReminderId(accountId, slot.dayOffset),
          title: title,
          body: '尚有 $amountText $currencyCode 未繳清，請盡快處理',
          scheduledDate: slot.scheduledDate,
        );
      }
      // 取消 [maxDays, kDueReminderMaxDayOffsetCap) 範圍內的殘留排程——天數被
      // 調低(例如從 10 改成 3)時,舊天數留下的排程要清掉。[0, maxDays) 範圍
      // 內「已經過去而跳過排程」的天數不用特別取消,通知已經觸發過或本來就
      // 沒排程過,見 [dueReminderScheduleSlots] 的說明。
      for (var offset = maxDays;
          offset < kDueReminderMaxDayOffsetCap;
          offset++) {
        await notificationUtil
            .cancelNotification(dueReminderId(accountId, offset));
      }
      logger.info('CreditCardReminder',
          '已调度到期連續提醒: accountId=$accountId, dueDate=$dueDate, maxDays=$maxDays');
    } catch (e, stack) {
      logger.error('CreditCardReminder', '调度到期連續提醒失败', e, stack);
    }
  }

  /// 取消③到期連續提醒(整個 id 範圍)。
  static Future<void> cancelDueReminders(int accountId) async {
    try {
      final notificationUtil = NotificationFactory.getInstance();
      for (var offset = 0; offset < kDueReminderMaxDayOffsetCap; offset++) {
        await notificationUtil
            .cancelNotification(dueReminderId(accountId, offset));
      }
      logger.info('CreditCardReminder', '已取消到期連續提醒: accountId=$accountId');
    } catch (e, stack) {
      logger.error('CreditCardReminder', '取消到期連續提醒失败', e, stack);
    }
  }
}
