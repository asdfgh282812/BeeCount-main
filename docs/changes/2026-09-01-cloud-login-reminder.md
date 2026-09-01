# App 端未登入雲端同步提醒

設計文件：`docs/superpowers/specs/2026-09-01-cloud-login-reminder-design.md`
（此目錄 gitignore，未進版控，僅本機留存設計依據）。

## 新增了什麼

App 每次冷啟動或從背景回到前景時,若使用者曾經設定過雲端同步(非 local)但目前
處於未登入狀態,會彈出一次提醒對話框,告知資料未在同步；對話框附「不再提示」
勾選框,勾選後永久關閉此提醒(即使之後又登出也不會恢復)。

## 檔案

- 新增 [lib/services/cloud_login_reminder_store.dart](../../lib/services/cloud_login_reminder_store.dart)
  —— 用 `SharedPreferences` 存一個 bool(`cloud_login_reminder_dismissed`),
  比照 `lib/ai/privacy/ai_privacy_consent.dart` 的風格,純本機、不入庫、不同步。
- 新增 [lib/widgets/cloud/cloud_login_reminder_dialog.dart](../../lib/widgets/cloud/cloud_login_reminder_dialog.dart)
  —— `maybeShowCloudLoginReminder(context, ref)` 是唯一入口,依序判斷:
  是否已勾選不再提示 → 是否曾設定雲端同步(讀 `activeCloudConfigProvider`)→
  `await ref.read(authServiceProvider.future)` 拿到已完整跑完 `initialize()`
  (含 session 還原/過期 refresh)的 auth service → `auth.currentUser` 是否為
  `null`。都成立才彈 `CloudLoginReminderDialog`(`AlertDialog` + `CheckboxListTile`
  + 「關閉」/「去登入」)。刻意用 `authServiceProvider` 而不是自己 await
  `beecountCloudProviderInstance`,因為前者是通用的 provider-agnostic 路徑
  (`lib/pages/cloud/cloud_sync_page.dart` 也是這樣拿 `currentUser` 的),同時
  涵蓋 BeeCount Cloud 與 Supabase 兩種需要登入的 provider,不必為每種 provider
  另外寫等待邏輯。
- 修改 [lib/app.dart](../../lib/app.dart)：`_checkCloudLoginReminder()` 新增
  觸發點,冷啟動走 `initState` 的 `addPostFrameCallback`,回到前景走
  `didChangeAppLifecycleState` 的 `resumed` 分支;`_loginReminderCheckInProgress`
  旗標防止兩個觸發點在極短時間內重疊執行(不是節流——只要使用者仍未登入且未
  勾選不再提示,每次前景本來就該有機會再提醒一次,這是刻意行為而非需要抑制的
  雜訊)。
- `lib/l10n/app_en.arb` / `lib/l10n/app_zh_TW.arb` 新增 5 個 key:
  `cloudLoginReminderTitle`/`Body`/`DontShowAgain`/`Dismiss`/`GoLogin`(依既有
  只維護這兩個語言檔的慣例,未動 `app_zh.arb`/`app_ko.arb`)。

## Out of scope

- 沒有 UI 入口可以把「不再提示」的旗標改回去(跟 `AiPrivacyConsentStore` 一致的
  一次性永久抑制設計,不過度設計；未來若需要「設定裡重新開啟提醒」可再加)。
- 不改動任何雲端同步核心邏輯,純粹讀取既有的 `activeCloudConfigProvider` /
  `authServiceProvider` 狀態。
