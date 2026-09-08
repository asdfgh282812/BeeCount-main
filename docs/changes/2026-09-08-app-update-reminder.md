# App 端新版本提醒

設計文件:`docs/superpowers/specs/2026-09-08-app-update-reminder-design.md`(本機
scratch,不入庫)。這次改動同時涉及 BeeCount-main(App)跟 BeeCount-Cloud
(server + web 管理後台)兩個獨立 repo。

## 背景

`docs/changes/2026-09-08-app-version-report.md` 只解決了「server 資料庫記錄的
裝置版本會過期」的問題,跟「使用者知不知道有新版本可以裝」無關。iOS 沒有
TestFlight(靠 NAS 文件管理手動分享 `.ipa`),Android 走 GitHub Releases + APK
但既有的 `UpdateService.checkUpdateWithUI()` 沒有接到任何 UI 入口。這次新增一個
獨立、輕量的「有新版本時跳提示對話框」機制,只對雲端同步後端是 `beecountCloud`
的使用者生效(因為要檢查的 server 是使用者自己控制的實例)。

## BeeCount-Cloud(server + web)

- `src/models.py`:新增單例表 `AppVersionCheckConfig`(固定 `id=1`),存
  `latest_version` + NAS WebDAV 連線設定(`nas_webdav_url/user/password`)+
  `last_checked_at/last_check_error`。
- `alembic/versions/0055_app_version_check_config.py`:對應建表 migration。
- `src/services/app_version_check.py`:核心偵測邏輯——對 `nas_webdav_url` 發一次
  帶 Basic Auth 的 GET,取回內容 `.strip()` 當候選版本號,`x.y`/`x.y.z` 格式檢查
  通過才寫回 `latest_version`;請求失敗或格式不合法只更新 `last_check_error`,
  保留舊版本號不動(避免髒資料污染)。`get_or_create_config` 提供「get or
  create id=1」語意,讀寫兩側都不用另外判斷「有沒有列」。
- `src/services/scheduled_jobs.py`:新增 job_key `check_latest_app_version`
  (預設 30 分鐘一次),掛進既有 `JOB_REGISTRY` + `_DEFAULT_JOB_CONFIGS`,自動
  出現在通用的「排程管理」後台頁面(可調頻率/停用/查看 last_run_at)。
- `src/routers/admin_app_version.py`:管理者 CRUD ——
  `GET/PUT /admin/app-version-config`(密碼欄位只回傳 `nas_webdav_password_set`
  布林值,不回顯明文;PUT 只有明確帶非空字串密碼才覆蓋,避免只改 URL 時被清空)+
  `POST /admin/app-version-config/check-now`(立即偵測,跟排程共用同一個
  `app_version_check.check_latest_app_version` 函式)。
- `src/routers/app_version.py`:公開端點 `GET /app-version/latest`(無需鑑權,
  只讀 DB 目前值,不即時打 NAS)。刻意用獨立 router(而非像 `/version` 那樣直接
  掛在 `main.py`),換取 `Depends(get_db)` 可測試性——`main.py` 少數幾個直接用
  `SessionLocal()` 的端點(`/ready` 等)繞過依賴注入,對純 `SELECT 1` 無妨,但
  這支端點的行為需要在測試裡用隔離資料庫驗證。
- `frontend/apps/web/src/pages/sections/AdminAppVersionPage.tsx` + 對應
  `api-client`(`admin.ts`/`types.ts`)+ 導覽(`nav.ts`/`router.ts`/
  `AvatarDropdown.tsx`/`App.tsx`)+ 三份 web i18n(en/zh-TW/zh-CN)。
- 測試:`tests/test_app_version_config.py`(admin GET/PUT 密碼語意、check-now
  三種情境、公開端點),並更新 `tests/test_scheduled_jobs.py` 既有的
  job 數量斷言(10 → 11)。

## BeeCount-main(App)

- `packages/flutter_cloud_sync/lib/src/providers/beecount_cloud_provider.dart`:
  新增 `fetchLatestAppVersion()`(`BeeCountCloudProvider` 委派層 +
  `BeeCountCloudStorageService` 實作層,比照既有 `fetchServerVersion()` 的公開
  端點、不需要 token 的寫法)+ 對應的 `BeeCountCloudLatestAppVersion` model。
- `lib/services/update/app_update_reminder_store.dart`:「不再提示」存的是版本
  字串(而非單純 bool)——跟 `CloudLoginReminderStore` 的永久關閉語意不同,
  這裡靠字串比對天然達成「逐版本失效」:server 端版本號更新後,舊的
  dismissedVersion 跟新版本號不相等,提醒自動恢復,不需要額外清除邏輯。
- `lib/widgets/cloud/app_update_reminder_dialog.dart`:`maybeShowAppUpdateReminder`
  + 對話框 UI。判斷順序:非 `beecountCloud` 後端 → skip(靠
  `beecountCloudProviderInstance` 內建的型別判斷,不用重複讀
  `activeCloudConfigProvider`);拉取失敗/`version` 為 null → skip;版本沒有比
  目前新 → skip;已被「不再提示」過這個版本 → skip。版本比較用一個獨立的小型
  三段式數字比較函式,刻意不重用 `UpdateChecker._isNewerVersion`(Android APK
  下載安裝流程的內部細節,語意跟這個純提醒功能無關)。
- `lib/widgets/cloud/cloud_login_reminder_dialog.dart`:`maybeShowCloudLoginReminder`
  回傳型別從 `Future<void>` 改成 `Future<bool>`(是否顯示了對話框),讓
  `app.dart` 可以判斷要不要接著顯示新版本提醒。
- `lib/app.dart`:原本的 `_checkCloudLoginReminder()` 擴充/重新命名為
  `_checkStartupReminders()`,依序呼叫登入提醒 → (沒顯示才)新版本提醒,兩者
  共用同一顆防重入旗標(原 `_loginReminderCheckInProgress` 重新命名為
  `_startupReminderCheckInProgress`),避免疊對話框。冷啟動
  (`initState`/`addPostFrameCallback`)與回到前景(`didChangeAppLifecycleState`
  的 `resumed` 分支)都改呼叫這個新入口。
- `lib/l10n/app_en.arb` + `app_zh_TW.arb`:新增 4 個 key(`appUpdateReminder`
  前綴),`appUpdateReminderBody` 帶 `current`/`latest` 兩個 placeholder。

## Out of scope(刻意不做)

- 不做 iOS OTA 一鍵安裝,純提醒去原本管道下載。
- 不做「強制更新」,單一按鈕「知道了」關閉即可。
- 不重用/修改既有 `UpdateChecker`/`UpdateService`(Android GitHub Release +
  APK 下載安裝那套死代碼),語意不同、完全獨立。
- 偵測(NAS WebDAV 輪詢)跟查詢(App 端 `/app-version/latest`)責任分離——
  App 每次打開不會間接連一次 NAS。
