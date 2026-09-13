# 通知中心新項目補跳本機系統通知

日期:2026-09-13
背景:`docs/changes/2026-08-17-notification-center.md` 上線後,
BeeCount Cloud 產生的 `card_due`(信用卡帳單已結算/即將到期)等通知只會顯示在
App 內的通知中心列表(輪詢 `GET /notifications`),不會跳出 iOS/Android 的系統
通知橫幅——使用者除非主動點開通知中心,否則感覺不到有新通知。使用者反饋這點
「即便 App 開著也不會跳信用卡相關通知」不符合預期。

## 範圍決策

這次只解決「App 有在跑輪詢時,新的未讀通知能跳出系統通知橫幅」,**不是**走
APNs 的真推播:
- App 完全關閉時不會補跳——現有架構沒有 WebSocket/APNs,只有前景輪詢
  (60 秒)+ App 回前景時的 `refresh()`,這次沒有新增背景喚醒機制。
- 點擊通知跳轉頁面不在這次範圍——`NotificationUtil.showNotification()` 介面
  目前沒有 `payload` 參數,`initialize()` 也沒接
  `onDidReceiveNotificationResponse`,要做要同時改 Android/iOS 兩份實作,
  範圍會變大;之後有需要再加。

## 改動內容

- **`lib/providers/notification_center_providers.dart`**:
  `NotificationCenterNotifier.refresh()` 拉到新的一頁後,額外呼叫新增的私有
  方法 `_notifyNewUnread(items)`——用 `SharedPreferences` 存一個
  `notification_center_last_notified_id` watermark(目前看過的最大
  `BeeCountCloudNotificationItem.id`),把 `id > watermark 且未讀` 的項目透過
  既有的 `NotificationFactory.getInstance().showNotification(...)`
  (`lib/utils/notification_factory.dart` → `notification_android.dart` /
  `notification_ios.dart`,底層是 `flutter_local_notifications` 的
  `.show()`,不是排程)跳出即時系統通知,然後把 watermark 更新成本次最大 id,
  避免同一則每次輪詢都重跳。
  - **首次執行**(本機還沒有 watermark,例如剛升級這個版本或剛登入)只記錄
    當下最大 id 當基準線、不倒著把既有未讀通通跳出來,避免一次跳一堆舊
    通知。
  - `showNotification(...)` 呼叫包 try/catch 靜默吞掉例外(未授權通知、
    非 Android/iOS 平台的 `UnsupportedError` 等),不讓通知子系統的失敗影響
    輪詢本身——比照 `auto_billing_service.dart` 既有的
    `_showNotification` 慣例。
  - 用 `unawaited(...)` 呼叫,不讓 `refresh()` 等通知(含權限檢查)跑完才
    return,避免下拉刷新的 spinner 多轉一段時間。

## 已知限制

- 只解決「App 有開/剛回前景」的情境。使用者回報的截圖裡的通知是 7 小時前
  產生的,若當時 App 沒開過,這次改完也不會補跳,只有之後新產生的才會跳。
- 要做到「App 完全關閉也會跳」需要導入真正的遠端推播(APNs),那是明顯更大的
  跨 repo(App + BeeCount-Cloud)工程,這次刻意不做。

## 測試

沒有新增自動化測試——`NotificationCenterNotifier` 既有的 `refresh`/
`markRead`/`markAllRead` 目前也都沒有直接的 provider 層單元測試,
`test/widgets/notification_center_page_test.dart` 是整個換成 spy 版
notifier(`_TestNotifier` 覆寫這三個方法)去測頁面渲染/互動,不會執行到真正的
`refresh()` 邏輯,這次新增的 `_notifyNewUnread` 私有邏輯依賴
`SharedPreferences` + `flutter_local_notifications` 平台通道,跟這個
codebase 對這類邊界程式碼的既有測試慣例一致,沒有另外補 mock。跑過
`flutter analyze` + 既有的
`notification_center_page_test.dart`/`notification_bell_button_test.dart`/
`notification_jump_target_test.dart` 三份測試全部通過。沒有實機/模擬器人工
驗證(這台機器沒有可用的 iOS Simulator/Android SDK)。
