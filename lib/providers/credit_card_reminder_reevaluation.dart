import 'package:shared_preferences/shared_preferences.dart';

import '../data/db.dart' as db;
import '../data/repositories/base_repository.dart';
import '../utils/card_reward_period.dart';
import '../utils/credit_card_payment.dart';
import 'credit_card_billing_providers.dart';
import 'credit_card_reminder_providers.dart';

/// 重新評估①提前提醒/②帳單結算提醒/③到期連續提醒並排程或取消。
///
/// 三種通知的「是否啟用/天數/提醒時間」是**全域**設定,不分卡——使用者在
/// `credit_card_reminder_overview_page.dart`(唯一的設定入口,寫入不帶
/// accountId 後綴的 SharedPreferences key)設一次,這裡讀出來套用到
/// [creditCardAccounts] 裡的每一張卡(2026-09-07 change doc 的範圍調整:
/// 原設計文件是逐卡各自的 UI/設定,使用者反饋覺得沒必要分卡,改成開了就
/// 每張卡都通知)。
///
/// [CreditCardReminderService] 本身刻意不碰 repo/Riverpod(見該類別開頭
/// docstring),這裡才是「有 repo 的呼叫端」——用
/// [creditCardDueByChildAsOf](跟帳戶列表「可繳款」徽章、`_dueAsOf` 同一套
/// watermark 公式,見 `credit_card_billing_providers.dart` 開頭 docstring)
/// 算好②③各自的 remainingDue/到期日,再以參數傳進 service 的方法;①提前
/// 提醒不需要算 remainingDue,直接用帳戶自己的 `paymentDueDay`。
///
/// 呼叫時機:App 啟動(`main.dart`)、App 回到前景(`app.dart` 的
/// `AppLifecycleState.resumed` 分支)、全域設定頁面(
/// `credit_card_reminder_overview_page.dart`)儲存時。
///
/// 範圍決策:只處理 `credit_card` 型帳戶,不含合併帳單群組主帳戶——群組的
/// 「應繳」需要彙總子帳戶,這裡刻意不擴大範圍,見
/// `docs/changes/2026-09-07-credit-card-notifications-badge-fix.md`。
Future<void> reevaluateAllCreditCardReminders({
  required BaseRepository repo,
  required List<db.Account> creditCardAccounts,
  bool skipIfCloudActive = false,
}) async {
  if (skipIfCloudActive) {
    for (final account in creditCardAccounts) {
      await CreditCardReminderService.cancelReminder(account.id);
      await CreditCardReminderService.cancelBillingReminder(account.id);
      await CreditCardReminderService.cancelDueReminders(account.id);
    }
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final hour = prefs.getInt('cc_reminder_hour') ?? 10;
  final minute = prefs.getInt('cc_reminder_minute') ?? 0;
  final advanceEnabled = prefs.getBool('cc_reminder_enabled') ?? false;
  final advanceDays = prefs.getInt('cc_reminder_days') ?? 3;
  final billingEnabled = prefs.getBool('cc_billing_reminder_enabled') ?? false;
  final dueEnabled = prefs.getBool('cc_due_reminder_enabled') ?? false;
  final dueMaxDays = prefs.getInt('cc_due_reminder_maxdays') ?? 3;

  for (final account in creditCardAccounts) {
    final accountId = account.id;
    final bankName = account.bankName;
    final displayName = (bankName != null && bankName.isNotEmpty)
        ? '$bankName${account.name}'
        : account.name;
    final paymentDueDay = account.paymentDueDay;

    // ①提前提醒
    if (advanceEnabled && paymentDueDay != null) {
      await CreditCardReminderService.scheduleReminder(
        accountId: accountId,
        accountName: displayName,
        paymentDueDay: paymentDueDay,
        daysBefore: advanceDays,
        hour: hour,
        minute: minute,
      );
    } else {
      await CreditCardReminderService.cancelReminder(accountId);
    }

    final billingDay = account.billingDay;
    if (billingDay == null || paymentDueDay == null) {
      await CreditCardReminderService.cancelBillingReminder(accountId);
      await CreditCardReminderService.cancelDueReminders(accountId);
      continue;
    }

    // ②帳單結算提醒
    if (billingEnabled) {
      final period = billingCyclePeriod(billingDay, 0);
      final due = await _remainingDueFor(repo, accountId, endOfDay(period.end));
      await CreditCardReminderService.scheduleBillingReminder(
        accountId: accountId,
        accountName: displayName,
        billingDate: period.end,
        remainingDue: due,
        currencyCode: account.currency,
        hour: hour,
        minute: minute,
      );
    } else {
      await CreditCardReminderService.cancelBillingReminder(accountId);
    }

    // ③到期連續提醒
    if (dueEnabled) {
      final closedOffset = mostRecentlyClosedBillingOffset(billingDay);
      final closedPeriod = billingCyclePeriod(billingDay, closedOffset);
      final due =
          await _remainingDueFor(repo, accountId, endOfDay(closedPeriod.end));
      final dueDate = due != null
          ? creditCardPaymentDueDate(closedPeriod.end, paymentDueDay)
          : null;
      await CreditCardReminderService.scheduleDueReminders(
        accountId: accountId,
        accountName: displayName,
        maxDays: dueMaxDays,
        remainingDue: due,
        dueDate: dueDate,
        currencyCode: account.currency,
        hour: hour,
        minute: minute,
      );
    } else {
      await CreditCardReminderService.cancelDueReminders(accountId);
    }
  }
}

Future<double?> _remainingDueFor(
    BaseRepository repo, int accountId, DateTime cutoff) async {
  final byChild = await creditCardDueByChildAsOf(repo, [accountId], cutoff);
  return byChild[accountId];
}
