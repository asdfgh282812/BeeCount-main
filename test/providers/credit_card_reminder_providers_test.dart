// ②帳單結算提醒/③到期連續提醒的純函式邏輯——排程/取消實際呼叫
// NotificationFactory.getInstance()，在非 Android/iOS 的測試環境會直接拋
// UnsupportedError（見 lib/utils/notification_factory.dart），這裡只測試不
// 依賴平台通道的部分：notification id 的碰撞規避（設計文件「id 範圍設計
// 說明」一節）與 [dueReminderScheduleSlots] 的排程時間計算。
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/providers/credit_card_reminder_providers.dart';

void main() {
  group('notification id 碰撞規避', () {
    test('①②③三種通知的 id 範圍互不重疊(accountId 0..9999)', () {
      final usedIds = <int>{};
      for (var accountId = 0; accountId <= 9999; accountId++) {
        final advanceId = 2000 + accountId;
        expect(usedIds.contains(advanceId), isFalse,
            reason: '①提前提醒 id 撞號: accountId=$accountId');
        usedIds.add(advanceId);

        final billingId =
            CreditCardReminderService.billingReminderId(accountId);
        expect(usedIds.contains(billingId), isFalse,
            reason: '②帳單結算提醒 id 撞號: accountId=$accountId');
        usedIds.add(billingId);
      }
      // ③跟①②分開驗證(dayOffset 維度會讓 accountId 迴圈開銷爆炸),但用同一組
      // accountId 抽樣檢查③本身跟①②的基底不會落進彼此的區間。
      for (var accountId = 0; accountId <= 9999; accountId++) {
        for (final dayOffset in [0, 1, 50, 98]) {
          final dueId =
              CreditCardReminderService.dueReminderId(accountId, dayOffset);
          expect(dueId >= kDueReminderIdBase, isTrue);
          expect(dueId < kDueReminderIdBase + 10000 * 100, isTrue);
          // ③的範圍(4,000,000 起)跟①(2000+accountId,accountId<=9999 时
          // 最大 11999)、②(3,000,000 起,accountId<=9999 时最大 3,009,999)
          // 完全不重疊。
          expect(dueId > 3009999, isTrue);
          expect(usedIds.contains(dueId), isFalse,
              reason:
                  '③到期連續提醒 id 撞到①/②: accountId=$accountId, dayOffset=$dayOffset');
        }
      }
    });

    test('②的 id 上界(accountId=9999)仍小於③的 id 下界(accountId=0)', () {
      final maxBillingId = CreditCardReminderService.billingReminderId(9999);
      final minDueId = CreditCardReminderService.dueReminderId(0, 0);
      expect(maxBillingId < minDueId, isTrue);
    });

    test('billingReminderId/dueReminderId 對同一個 accountId 是穩定的純函式', () {
      expect(CreditCardReminderService.billingReminderId(42),
          CreditCardReminderService.billingReminderId(42));
      expect(CreditCardReminderService.dueReminderId(42, 3),
          CreditCardReminderService.dueReminderId(42, 3));
      expect(CreditCardReminderService.dueReminderId(42, 3),
          isNot(CreditCardReminderService.dueReminderId(42, 4)));
    });
  });

  group('dueReminderScheduleSlots', () {
    test('回傳 dueDate ~ dueDate+(maxDays-1) 共 maxDays 個排程時間點', () {
      final dueDate = DateTime(2026, 9, 20);
      final slots = dueReminderScheduleSlots(
        dueDate: dueDate,
        maxDays: 3,
        now: DateTime(2026, 9, 1),
        hour: 10,
        minute: 30,
      );
      expect(slots.length, 3);
      expect(slots[0].dayOffset, 0);
      expect(slots[0].scheduledDate, DateTime(2026, 9, 20, 10, 30));
      expect(slots[1].scheduledDate, DateTime(2026, 9, 21, 10, 30));
      expect(slots[2].scheduledDate, DateTime(2026, 9, 22, 10, 30));
    });

    test('已經過去的天數會被跳過,不補發', () {
      final dueDate = DateTime(2026, 9, 20);
      // now 落在第 2 天(offset=1)的排程時間之後 → offset 0、1 都已過去。
      final slots = dueReminderScheduleSlots(
        dueDate: dueDate,
        maxDays: 3,
        now: DateTime(2026, 9, 21, 11, 0),
        hour: 10,
        minute: 0,
      );
      expect(slots.map((s) => s.dayOffset), [2]);
      expect(slots.single.scheduledDate, DateTime(2026, 9, 22, 10, 0));
    });

    test('全部天數都已過去時回傳空清單', () {
      final dueDate = DateTime(2026, 9, 20);
      final slots = dueReminderScheduleSlots(
        dueDate: dueDate,
        maxDays: 3,
        now: DateTime(2026, 10, 1),
      );
      expect(slots, isEmpty);
    });

    test('maxDays=0 回傳空清單', () {
      final slots = dueReminderScheduleSlots(
        dueDate: DateTime(2026, 9, 20),
        maxDays: 0,
        now: DateTime(2026, 9, 1),
      );
      expect(slots, isEmpty);
    });
  });
}
