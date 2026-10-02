# 通知設定綁帳號(跨裝置同步)

**入口**:我的 → 自動化 → 記帳提醒 / 信用卡提醒(頁面本身不變,只是設定改為跟帳號走)。

## 為什麼
記帳提醒與信用卡提醒原本只存在本機 SharedPreferences,換裝置/重裝就消失。改為存到 BeeCount Cloud 的 `/profile/me`,與 appearance、ai_config 同一套機制。

## 範圍
同步 10 個 key(wire key 與 prefs key 同名,snake_case):`reminder_enabled/hour/minute`、`cc_reminder_hour/minute/enabled/days`、`cc_billing_reminder_enabled`、`cc_due_reminder_enabled/maxdays`。
**不同步**:通知權限、排程 ID、`notification_center_last_notified_id`(裝置狀態)。預算提醒本來就在 project 實體內同步,未動。

## 變更
**BeeCount-Cloud**:`alembic/versions/0063_notification_settings.py` 新增 `user_profiles.notification_settings_json`(nullable);`models.py`、`schemas.py`、`routers/profile.py` 的 GET/PATCH 加 `notification_settings`(整包替換,`{}` 清空,未帶不動)。WS `profile_change` payload 不帶此欄位,客戶端收到後自行 GET。測試:`tests/test_profile_notification_settings.py`。

**App**
- `lib/services/system/notification_settings_sync.dart`:schema 單一來源,`snapshot()` / `applyFromServer()` / `reconcile()` / `onChanged` 回呼。
- `packages/flutter_cloud_sync`:`BeeCountCloudProfile.notificationSettings`、`updateMyProfileNotificationSettings`。
- `sync_events.dart` / `sync_engine_profile.dart`:新增 `ProfileField.notificationSettings`。
- `sync_providers.dart`:下行套用(寫 prefs → `ReminderSettingsNotifier.reload()` 重排程 → `reevaluateAllCreditCardReminders`)、`onChanged` 指派為推送、`reconcileProfileToServer` 首次對帳。
- `reminder_providers.dart`:`_saveSettings` 後通知推送;新增 `reload()`。信用卡設定頁 `_save` 同樣通知。

## 取捨
- 衝突策略沿用 profile 慣例:last-write-wins,首次綁定時 server 有值則以 server 為準,server 空而本機有設定才補推。
- 推送是整包快照,裝置若未先 pull 就改設定,會以預設值覆蓋其他欄位。bootstrap 會先 `syncMyProfile`,實務上風險低,未額外加版本號。
- 雲端啟用時信用卡本機提醒仍會被取消(改由 server cron 通知),此行為未變;設定值本身照樣同步。
- 信用卡設定頁開啟中收到下行不會即時刷新畫面(重進頁面即更新)。

## 部署順序
先部署 Cloud(跑 migration 0063)再發 App;舊 Cloud 會忽略該欄位,App 端推送靜默失敗不影響使用。
