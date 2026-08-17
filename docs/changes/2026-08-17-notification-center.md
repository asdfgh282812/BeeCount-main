# 通知中心(App 端接上 BeeCount Cloud 服務端通知)

日期:2026-08-17
背景:BeeCount Cloud(`../BeeCount-Cloud`)已經有一套完整的「通知中心」——
`notifications` 表(user-global,**不是** sync entity,不進 `sync_changes`/
projection),由服務端各處業務邏輯(週期性交易到期/餘額不足、信用卡繳款日
cron、信用卡自動扣款、紅利回饋派發)呼叫 `create_notification()` 寫入一行,
Web 前端用 `GET/POST /notifications*` 輪詢展示(`NotificationBell.tsx`)。
App 端原本完全沒有對應功能。使用者明確要求:「跟 Web 端一樣,通知都由 Web
(其實是服務端)發起,App 不用自己有通知的規則」——即 App 只負責拉取/已讀
標記,不做任何本地通知內容的計算判斷。

## 範圍與依據

- Cloud 目前實際會寫入的 category 只有三種(`src/services/notifications.py`
  的 `Literal["reminder","budget_alert","card_due","card_reward","system"]`
  裡,`budget_alert`/`system` 目前零 producer,是預留欄位):
  - `reminder`:週期性交易視窗自動續期(payload `{ledgerId, recurringRuleId}`)
    /轉帳因餘額不足跳過(`{..., kind:"insufficient_funds"}`)——
    `recurring_materializer.py`,24h cron。分期還款結清的 `reminder` payload
    帶 `installmentPlanId`,App 沒有分期實體,忽略。
  - `card_due`:信用卡帳單/繳款日狀態(`{accountId, cycleEnd, kind, ledgerId}`)
    ——`credit_card_reminders.py`,15 分鐘 cron。
  - `card_reward`:紅利回饋派發(`{ruleId, accountId, periodEnd, ledgerId}`)
    ——`card_reward_payout.py`,5 分鐘 cron。
- 沒有 WebSocket 推播(`notifications.py` 檔頭註解已言明),App 跟 Web 一樣
  用輪詢,週期抓齊 60 秒(同 Web `NotificationBell.tsx` 的
  `POLL_INTERVAL_MS`)。
- 只有 BeeCount Cloud 是當前啟用的同步後端時才顯示/輪詢——其它後端
  (Supabase/WebDAV/S3/iCloud/純本地)沒有服務端生成通知,整個功能對它們
  不存在(gate 在 `beecountCloudProviderInstance` 上)。

## 改動內容

- **`packages/flutter_cloud_sync/lib/src/providers/beecount_cloud_provider.dart`**:
  新增 `fetchNotifications`/`markNotificationRead`/`markAllNotificationsRead`
  三個方法(`BeeCountCloudStorageService` 實作 + `BeeCountCloudProvider` 轉發),
  跟既有 `listDevices` 走一樣的 `_authedRequest`(Bearer token 自動帶、401 自動
  重試一次刷新 session)。新增 `BeeCountCloudNotificationItem`/
  `BeeCountCloudNotificationPage` model class。
- **`lib/data/repositories/{ledger_repository,account_repository}.dart`** +
  對應 `local_*_repository.dart` 實作 + `local_repository.dart` 轉發:新增
  `getLedgerBySyncId`/`getAccountBySyncId`——payload 裡的 `ledgerId`/
  `accountId` 是 server 端的 external_id/syncId,需要反查回本機 int id 才能
  導航到正確頁面。`RecurringRuleRepository.getRuleBySyncId` 原本就有,沒改。
- **`lib/providers/notification_center_providers.dart`**(新檔):
  `NotificationCenterState`(items/unreadCount/loading/error) +
  `NotificationCenterNotifier extends StateNotifier`。用**建構時捕捉**
  `BeeCountCloudProvider?`(由 provider 的 builder callback
  `ref.watch(beecountCloudProviderInstance)` 決定,值變化時 Riverpod 會整個
  重建 notifier,舊實例連同它的 `Timer` 一起 dispose)——這是這個 codebase
  既有的「gate 在另一個 provider 上」寫法(同 `repositoryProvider` watch
  `activeCloudConfigProvider` 重建 `LocalRepository` 的模式),沒有引入新的
  `Notifier`/`riverpod_generator` API(這個 repo 目前全部是 `StateNotifier`,
  刻意保持一致)。非 Cloud 後端時建構子直接不啟動輪詢。
  `markRead`/`markAllRead` 走樂觀更新 + 失敗時整個 `refresh()`。
- **`lib/widgets/biz/notification_bell_button.dart`**(新檔):首頁頂部鈴鐺,
  gate 在 `beecountCloudProviderInstance`,未讀數 > 0 疊一個手刻圓角徽章
  (這個 codebase 沒有用 Flutter 內建 `Badge()` widget,統一手刻
  `Positioned`+`Container`)。拆成獨立 widget 而不是直接寫進
  `lib/pages/main/home_page.dart`,是為了不用揹首頁整頁的重量級 provider
  依賴就能單獨測試。
- **`lib/pages/notifications/notification_center_page.dart`**(新檔):列表頁
  (`PrimaryHeader` + 全部標為已讀 + 空/錯誤重試狀態 + 下拉刷新)。點擊一則
  通知的跳轉邏輯拆成獨立的 `resolveNotificationJumpTarget()` 函式(輸入
  payload + repo,輸出「要跳去哪」而不直接碰 `Navigator`),優先序對齊 Web
  `NotificationBell.tsx handleJumpToDetail`:`accountId`(涵蓋 `card_due`/
  `card_reward`)優先於 `recurringRuleId`(涵蓋 `reminder`),App 沒有
  `debtId`/`installmentPlanId`/純 `txId` 對應的頁面,這幾支直接不處理、視同
  無跳轉目標。跳轉前先用 payload 的 `ledgerId` 反查本機帳本,跟目前選中的不
  同就先切過去(`currentLedgerIdProvider`),否則目標頁會查不到資料;帳本/
  實體在本機都查不到時顯示 toast,不跳轉、不崩潰。
- **`lib/providers/credit_card_reminder_providers.dart`** +
  **`lib/pages/account/account_edit_page.dart`** + **`lib/main.dart`**:
  `CreditCardReminderService.scheduleReminder`/`restoreAllReminders` 新增
  `skipIfCloudActive` 參數(呼叫端算好傳入,類別本身不依賴 Riverpod)。
  BeeCount Cloud 啟用時,信用卡繳款日的本地 OS 排程改成一律取消——Cloud 端
  `card_due` cron 已經會把同樣的提醒寫進通知中心,本地再排一次會讓使用者收到
  兩次提醒。非 Cloud 後端(本地/其它備份後端)行為完全不變,因為那些使用者
  沒有服務端幫忙生成提醒。另一個既有的本地提醒功能——
  `lib/pages/settings/reminder_settings_page.dart`(每天固定時間提醒記帳的
  習慣提醒)——跟 Cloud 完全沒有對應概念(Cloud 不追蹤「今天有沒有記帳」),
  維持原樣未動。
- **l10n**:新 key 只加進 `app_en.arb` + `app_zh_TW.arb`(見
  [[feedback-l10n-policy-change]] / 2026-08-17 起的既定政策),`app_zh.arb`/
  `app_ko.arb` 不動。

## 已知 v1 範圍取捨

- 列表固定 `limit: 50`、無無限捲動——`unread_count` 徽章數字是服務端算的全域
  未讀數,不受分頁影響,永遠準確;只有「列表本身可能看不到 50 則以前的舊
  通知」這個限制,之後有需要再加。
- 背景輪詢失敗(含 401 刷新失敗)不會強制登出——只在使用者下次開啟通知頁時
  用重試狀態呈現,避免一次背景輪詢失敗就把人踢出登入。
- `budget_alert`/`system` 目前服務端零 producer,但頁面的 fallback icon/
  無跳轉分支已經正確處理,之後服務端加上對應功能不用動 App 這邊。

## 測試

- `test/data/notification_jump_target_test.dart`:純 Dart + 真的記憶體 Drift
  db,覆蓋 `resolveNotificationJumpTarget` 全部分支(none/account/rule/
  not-found/ledger-not-synced/優先序/沒有 ledgerId 也能解析)。
- `test/widgets/notification_center_page_test.dart`:`notificationCenterProvider`
  整個換成 spy notifier,覆蓋空狀態、錯誤+重試、未讀視覺區分、全部已讀按鈕
  的啟用/停用與點擊、下拉刷新、無跳轉目標時只標已讀不導航。**沒有**在這裡
  重覆測試「點擊後真的導航進 AccountDetailPage/RecurringRuleListPage」——
  那兩個頁面的依賴很重,且「該不該跳轉、跳去哪」這個真正的邏輯已經被
  `resolveNotificationJumpTarget` 的測試覆蓋,`Navigator.push(...)` 本身只是
  套用這個 codebase 既有的樣板寫法(同 `automation_page.dart`)。
- `test/widgets/notification_bell_button_test.dart`:gate 邏輯(非 Cloud 後端
  時鈴鐺完全不顯示)、徽章顯示/隱藏/99+、點擊導航。
- 未做:`fetchNotifications`/`markNotificationRead`/`markAllNotificationsRead`
  這幾個 raw HTTP 方法沒有對真的 server 打測試,跟這個 codebase 對
  `listDevices` 等既有方法的測試慣例一致(共用的 `_authedRequest` 401 重試
  邏輯已經是既有、通用的機制)。
- 沒有實機/模擬器人工驗證這一輪(跟 recurring-rule 那次一樣,這台機器沒有可
  用的 iOS Simulator/Android SDK)。之後有可用裝置建議手動走一遍:用有
  BeeCount Cloud 帳號、至少一張信用卡+一條週期規則的帳號登入,確認鈴鐺
  顯示、列表正確、點擊能跳轉到對的帳戶、全部已讀能清空徽章。
