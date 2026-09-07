# 信用卡繳費通知擴充 + iOS 通知徽章清除 bug 修復

設計文件:`docs/superpowers/specs/2026-09-07-credit-card-notifications-badge-fix-design.md`
(該目錄已 gitignore，不會進版控，這裡記錄實作結果與跟設計文件的落差)。

## 範圍調整(2026-09-07 追加,跟設計文件最大的落差)

初版完全照設計文件做成「逐卡設定」——`CreditCardReminderOverviewPage` 列出
每一張信用卡帳戶,點進去 push 到該帳戶的 `AccountEditPage`,在裡面各自開關
①②③。使用者實際試用後反饋兩個問題:(1) 卡多的時候要逐卡設定太麻煩,
「不需要分卡，只要開了，就每張卡都要通知」;(2) 合併帳單群組的主帳戶(如
「XX 帳戶」)不是 `credit_card` 型態,點進去的 `AccountEditPage` 根本沒有
還款提醒欄位可設定,是個死路。

因此把①②③(含既有、這次任務之前就有的①提前提醒)全部改成**全域設定**,
不分卡:

- SharedPreferences key 從 `cc_reminder_enabled_$accountId` 這種帶
  accountId 後綴的形式,改成不帶後綴的全域 key:`cc_reminder_hour`/
  `cc_reminder_minute`(共用提醒時間)、`cc_reminder_enabled`/
  `cc_reminder_days`(①)、`cc_billing_reminder_enabled`(②)、
  `cc_due_reminder_enabled`/`cc_due_reminder_maxdays`(③)。
- `account_edit_page.dart` 的「還款提醒」卡片(含這次任務之前就有的①提前
  提醒 UI)整個移除——不再需要進到單一帳戶的編輯頁設定通知,`_reminderEnabled`
  等 7 個 state 欄位、`_loadReminderSettings`/`_saveReminderSettings`/
  `_pickReminderTime` 三個方法、以及儲存時呼叫 `_saveReminderSettings` 的
  邏輯全部刪除。
- `credit_card_reminder_overview_page.dart` 從「逐卡列表 + 點進去設定」改寫成
  單一設定頁:提醒時間 + ①②③三個開關(②③沿用原本的天數 `ChoiceChip`),
  每個開關/選項改動立刻 `setState` + 存 prefs + 呼叫下面的
  `reevaluateAllCreditCardReminders`,套用到當下所有信用卡帳戶,不用等下次
  App 啟動/回到前景。頁面上方保留一行「套用於 N 張信用卡帳戶」的提示
  (`creditCardReminderAppliesToCount`),取代原本的逐卡列表,單純讓使用者
  知道套用範圍,不能點擊。
- `credit_card_reminder_providers.dart`:`CreditCardReminderService.
  restoreAllReminders`(舊的①專用恢復邏輯,讀逐卡 key)整個刪除,合併進下面
  的 `reevaluateAllCreditCardReminders`——現在①②③恢復/重新評估邏輯統一在
  一個函式裡,單次讀取全域設定套用到傳入的帳戶清單。`scheduleReminder`/
  `cancelReminder`/`scheduleBillingReminder`/`cancelBillingReminder`/
  `scheduleDueReminders`/`cancelDueReminders`(逐卡各自的排程/取消方法,接受
  `accountId` + 明確參數)不變——「全域設定」只影響「誰決定要不要排程/用什麼
  參數排程」,實際排程 API 仍是逐卡呼叫,notification id 也還是逐卡各自的
  (`2000+accountId`/`kBillingReminderIdBase+accountId`/
  `kDueReminderIdBase+accountId*100+dayOffset`),沒有變成「一個通知涵蓋所有
  卡」。
- `credit_card_reminder_reevaluation.dart`:`reevaluateBillingAndDueReminders`
  (原本只處理②③)重新命名/擴充為 `reevaluateAllCreditCardReminders`(處理
  ①②③),簽名不變(`repo`/`creditCardAccounts`/`skipIfCloudActive`),內部
  一次性讀取全域 prefs,迴圈套用到 `creditCardAccounts` 裡的每一張卡。
  `main.dart`(App 啟動)、`app.dart`(`AppLifecycleState.resumed`)呼叫點
  同步改名;`main.dart` 原本並列呼叫的
  `CreditCardReminderService.restoreAllReminders` 那行整個刪除,啟動時只呼叫
  一次 `reevaluateAllCreditCardReminders` 就涵蓋①②③。
- l10n:移除不再需要的逐卡摘要字串
  `creditCardReminderOverviewNotConfigured`/`creditCardReminderSummaryAdvance`/
  `creditCardReminderSummaryBilling`/`creditCardReminderSummaryDue`,新增
  `creditCardReminderAppliesToCount`(`{count}` 張信用卡帳戶的提示文字)。
  `creditCardReminderTimeTitle`/`creditCardReminderTitle`/`Desc`/
  `DaysBefore`/`creditCardBillingReminderTitle`/`Desc`/
  `creditCardDueReminderTitle`/`Desc`/`MaxDays` 幾組字串沿用不變(從
  `account_edit_page.dart` 搬到 `credit_card_reminder_overview_page.dart`,
  意思不變)。
- 測試:`test/providers/credit_card_reminder_reevaluation_test.dart` 改用全域
  prefs key(不帶 accountId 後綴),新增「同一組全域設定套用到兩張不同信用卡
  帳戶都不拋例外」的案例,對齊「開了就每張卡都通知」的核心訴求。
  `test/providers/credit_card_reminder_providers_test.dart`(notification id
  防撞、`dueReminderScheduleSlots` 排程時間計算)不受影響,原樣保留。

以下「新增②帳單結算提醒 / ③到期連續提醒」小節記錄的是**初版**(逐卡設定)的
實作,大部分邏輯(id 設計、`dueReminderScheduleSlots`、②③各自的排程判斷)
在改成全域設定後仍然成立,只是「誰觸發、用什麼參數」的來源從「逐卡 prefs」
換成「全域 prefs」,閱讀時請對照上面這節的调整。

## 新增②帳單結算提醒 / ③到期連續提醒(初版,見上方「範圍調整」)

- [lib/providers/credit_card_reminder_providers.dart](../../lib/providers/credit_card_reminder_providers.dart):
  `CreditCardReminderService` 新增 `scheduleBillingReminder`/`cancelBillingReminder`
  (②)、`scheduleDueReminders`/`cancelDueReminders`(③)。維持既有「service 本身
  不碰 Riverpod/repo」的原則——`remainingDue`/`dueDate` 全部由呼叫端算好以參數
  傳入。
  - notification id:②`3_000_000 + accountId`,③`4_000_000 + accountId*100 +
    dayOffset`(`dayOffset` 上限抓 99,見 `kDueReminderMaxDayOffsetCap`)。id
    範圍設計的防撞理由見設計文件「id 範圍設計說明」一節,程式碼裡也留了
    對應 docstring。
  - 新增純函式 `dueReminderScheduleSlots`,把「哪幾天需要排程」跟「哪個
    scheduledDate」抽出來單獨測試(見下方測試小節)——排程時間早於 `now`
    的天數直接跳過,不補發,避免用過去時間點觸發本地通知立即彈出。
- [lib/providers/credit_card_reminder_reevaluation.dart](../../lib/providers/credit_card_reminder_reevaluation.dart)(新檔):
  `reevaluateBillingAndDueReminders` 是「有 repo 的呼叫端」,用
  `credit_card_billing_providers.dart` 既有的 `creditCardDueByChildAsOf`
  (跟帳戶列表「可繳款」徽章同一套 watermark 公式)算好 remainingDue/dueDate
  再呼叫 service。呼叫時機三處:
  - [lib/main.dart](../../lib/main.dart):App 啟動,跟既有
    `CreditCardReminderService.restoreAllReminders` 並列呼叫。
  - [lib/app.dart:856](../../lib/app.dart) 附近的 `AppLifecycleState.resumed`
    分支:新增 `_reevaluateCreditCardReminders()`,跟既有 `_checkAppLockOnResume`/
    `_updateWidget` 並列。
  - [lib/pages/account/account_edit_page.dart](../../lib/pages/account/account_edit_page.dart)
    的 `_saveReminderSettings`:存檔後立刻重新評估,不用等下次啟動/回到前景。
- **範圍決策(跟設計文件的落差)**:`reevaluateBillingAndDueReminders` 只處理
  `credit_card` 型帳戶,不含合併帳單群組主帳戶——群組的「應繳」需要彙總子
  帳戶,設計文件通篇只討論單一 `accountId` 的情境,沒有討論群組語意,這裡
  刻意不擴大範圍。`account_edit_page.dart` 的還款提醒卡片維持既有的
  `if (isCreditCard)` 顯示條件不變(不擴大到 `account_group`)。

## UI 變更(現況,已套用上方「範圍調整」)

- `account_edit_page.dart`:不再有任何還款提醒相關 UI/state/方法——整段
  「還款提醒」`SectionCard`(含這次任務之前就有的①提前提醒)已移除,見上方
  「範圍調整」。
- [lib/pages/settings/credit_card_reminder_overview_page.dart](../../lib/pages/settings/credit_card_reminder_overview_page.dart):
  單一全域設定頁——「提醒時間」`ListTile` + ①提前提醒/②帳單結算提醒/③到期
  連續提醒三個 `SwitchListTile`(②③沿用 `[1,3,5,7]`/`[3,5,7,10]` 天
  `ChoiceChip`),每個改動立刻存全域 prefs + 呼叫
  `reevaluateAllCreditCardReminders` 套用到所有信用卡帳戶。頁面上方顯示
  「套用於 N 張信用卡帳戶」,純資訊性,不可點擊,也不再列出個別帳戶。
- [lib/pages/settings/automation_page.dart](../../lib/pages/settings/automation_page.dart):
  原本單一 `SectionCard` 拆成「週期記帳」+「通知」兩個,「通知」內含「記帳
  提醒」(搬移)+「信用卡繳費提醒」(新增,導到上面的全域設定頁)。

## iOS 通知徽章清除

- [ios/Runner/AppDelegate.swift](../../ios/Runner/AppDelegate.swift):新增
  `com.beecount.app/badge` method channel,`clearBadge` 呼叫
  `UIApplication.shared.applicationIconBadgeNumber = 0`。
- [lib/utils/ios_badge_util.dart](../../lib/utils/ios_badge_util.dart)(新檔):
  `clearAppIconBadge()` 封裝該 method channel,非 iOS 平台 no-op。
- `app.dart` 的 `AppLifecycleState.resumed` 分支新增一行呼叫。

## l10n

`app_en.arb` + `app_zh_TW.arb`(本專案目前只維護這兩個,見既有 l10n 政策)
新增:`creditCardReminderTimeTitle`、`creditCardReminderTitle`/`Desc`/
`DaysBefore`、`creditCardBillingReminderTitle`/`Desc`、
`creditCardDueReminderTitle`/`Desc`/`MaxDays`、
`automationNotificationSectionTitle`、`automationCreditCardReminderTile`/
`Subtitle`、`creditCardReminderOverviewTitle`/`Empty`、
`creditCardReminderAppliesToCount`(現況;`NotConfigured`/
`creditCardReminderSummaryAdvance`/`Billing`/`Due` 是初版逐卡摘要用的字串,
改成全域設定後已刪除)。通知本身的標題/內文沿用既有①提前提醒的做法,不走
l10n(硬編碼中文字串,見 `CreditCardReminderService` 既有寫法),只有 UI 上
的開關/標籤走 l10n。

## 測試

- [test/providers/credit_card_reminder_providers_test.dart](../../test/providers/credit_card_reminder_providers_test.dart):
  notification id 防撞(對齐設計文件「id 範圍設計說明」)、`dueReminderScheduleSlots`
  的排程時間計算(含「已過去的天數會被跳過」)。不受全域設定調整影響,原樣
  保留。
- [test/providers/credit_card_reminder_reevaluation_test.dart](../../test/providers/credit_card_reminder_reevaluation_test.dart):
  用記憶體 Drift DB 驗證 `reevaluateAllCreditCardReminders`(現名)在各種
  開關/資料組合下不會拋例外、正確讀 repo/全域 SharedPreferences,含「同一組
  全域設定套用到兩張不同信用卡帳戶」的案例。
- **已知限制**:`scheduleBillingReminder`/`scheduleDueReminders` 實際呼叫
  `NotificationFactory.getInstance()`,在非 Android/iOS 的測試環境(`flutter
  test` 跑在 host 上)會拋 `UnsupportedError`——這層例外在
  `CreditCardReminderService` 內部被吞掉(記 log,不外拋),所以測試只能驗證
  「不會拋例外、輸入輸出邏輯正確」,無法斷言真的呼叫到通知外掛排程了什麼。
  `NotificationFactory._instance` 目前沒有測試用的注入介面,新增一個純粹為
  了這次測試的 setter 超出本次設計文件範圍,故未做。
- Badge 清除、UI 開關/時間選擇器需要模擬器手動驗證,無法自動化測試(跟設計
  文件「測試考量」一節一致)。
