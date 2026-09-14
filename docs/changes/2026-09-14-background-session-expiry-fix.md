# 修正 App 掛後台一段時間後被強制登出（BeeCount Cloud）

## 問題現象

使用者回報：App 沒有被系統殺掉、只是長時間放在後台，切回前景後偶爾會被判定為「未登入」，
需要重新輸入帳密登入。

## 根因

BeeCount Cloud 後端使用 rotating refresh token：每次呼叫 `/auth/refresh` 都會讓舊的
refresh token 立即失效，回傳一組新的 access/refresh token。

`createCloudServices()`
（[provider_factory.dart](../../packages/flutter_cloud_sync/lib/src/config/provider_factory.dart)）
每次被呼叫都會 `BeeCountCloudProvider()` 產生一個全新物件，而 App 裡實際上有多處
各自獨立呼叫它、各自持有一份 `BeeCountCloudAuthService` 實例，彼此完全不知道對方存在：

- `authServiceProvider`（[sync_providers.dart:148](../../lib/providers/sync_providers.dart)）— UI
  側（登入提醒對話框等）在用的實例。
- `beecountCloudProviderInstance`（[sync_providers.dart:498](../../lib/providers/sync_providers.dart)）
  — `SyncEngine` 實際拿去做所有 push/pull/realtime 的實例，經常在跑，token 過期就會自己刷新。
- 另外 `transactions_sync_manager.dart`、`devices_page.dart`、`cloud_service_page.dart`
  也各自獨立呼叫過。

這些實例的 `_session`（含 refresh token）只存在各自記憶體裡，但共用同一把
SharedPreferences 持久化 key。當 App 背景待得夠久、access token 過期後回到前景：

1. `SyncEngine` 那個「經常在跑」的實例可能早就自己刷新過一輪，把新 session 存進了
   SharedPreferences，同時讓它記憶體裡舊的 refresh token 作廢。
2. `didChangeAppLifecycleState(resumed)` 觸發的 `_checkStartupReminders()`
   （[app.dart:874-893](../../lib/app.dart)）會去讀 `authServiceProvider` 那個「比較閒」的舊實例的
   `currentUser`，它記憶體裡還是那份「已經被別人轉過、現在已失效」的舊 refresh token。
3. 用這個已失效的 refresh token 去打 `/auth/refresh` → server 回 401 → 舊程式碼判斷為
   「refresh token 真的失效，需要重新登入」→ `_clearSession()` **清掉全域
   SharedPreferences session**（即使另一個實例手上其實握有仍然合法的新 session）。
4. 全 App（含 SyncEngine）下次讀到的都是「沒有 session」，UI 顯示未登入。

這條 race 在原始碼裡其實已經被作者部分意識到並寫了很長的中文註解
（見 `beecount_cloud_provider.dart` 的 `_refreshInFlight` 欄位），但當時只用
in-flight future 去重擋住「**同一個實例內**」的併發呼叫，沒考慮到 App 裡本來就有多個
獨立實例共享同一把持久化 key 的情況。

## 修法

沒有改動 Riverpod provider 結構（那會是更大的架構調整，風險/影響面都大很多），而是直接在
[`BeeCountCloudAuthService._doRefreshSession()`](../../packages/flutter_cloud_sync/lib/src/providers/beecount_cloud_provider.dart)
這個唯一的刷新入口把「跨實例」的情況也考慮進去，讓修法對「未來又新增一個獨立呼叫點」這種情況
一樣有效：

1. **刷新前**先重新讀一次 SharedPreferences（新增 `_loadSessionFromDisk()`）。如果磁碟上已經有
   別的實例更早刷新出來、目前仍未過期的 session，直接採用它，不再拿記憶體裡這份可能已作廢的
   refresh token 去發一個註定失敗的請求。
2. 如果磁碟上的 refresh token 跟記憶體裡不一樣（代表別的實例已經轉過一輪，只是新
   access token 恰好也過期了），優先用磁碟上這份去刷新，而不是用已知會被 revoke 的舊 token。
3. **刷新失敗（401/403）後、判定為「真的要登出」之前**，再讀一次磁碟：如果這期間另一個實例已經
   用更新的 refresh token 刷新成功，採用那份，不要用這次失敗的結果去清掉一個其實仍然合法的
   全域 session。只有磁碟上也沒有更新、合法的 session 時，才真的清 session、要求使用者重新登入。

## 影響範圍 / 刻意不做的事

- 只修改了 `flutter_cloud_sync` 套件裡的 auth service，UI/Provider 層完全沒動。
- 沒有把多個 `createCloudServices()` 呼叫點合併成單例（那是更徹底但風險更高的架構修法，
  之後如果同一問題還有其他變形再考慮）。
- Supabase 後端不受影響：`supabase_flutter` 套件本身的 `SupabaseAuth` 已經是
  `WidgetsBindingObserver`，resume 時會自己呼叫 `startAutoRefresh()` 補刷新，沒有這個問題。
