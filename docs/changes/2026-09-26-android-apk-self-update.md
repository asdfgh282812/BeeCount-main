# Android APK 應用內自我更新（Cloudflare R2）

## 背景

Android 版不上 Google Play，APK 自己放在 Cloudflare R2
(`https://pub-6fbd073a81084e04a716c50549e721b7.r2.dev/`) 分發。原作者留下的
`UpdateChecker` / `UpdateDownloader` / `UpdateInstaller` 整套 APK 下載安裝流程
一直是死代碼（沒有任何 UI 入口），而且查的是**原作者**的 GitHub Release
(`TNT-Likely/BeeCount`)——如果接上，會下載到別人簽章的 APK，覆蓋安裝必定失敗。
這次把版本來源換成 R2 上的 `version.json`，並接上啟動檢查與手動入口。

iOS 完全不受影響：所有 APK 相關程式碼都在 `Platform.isAndroid` 分支裡，iOS 啟動時
仍走 `docs/changes/2026-09-08-app-update-reminder.md` 的「純提醒」。

## 使用者入口

- **自動**：App 冷啟動 / 回到前景時（`app.dart` 的 `_checkStartupReminders`），
  有新版就跳「發現新版本 x.y.z」對話框 → 「立即更新」下載並呼叫系統安裝程式。
  按「稍後」後同一版本 24 小時內不再自動跳出。
- **手動**：我的 → 關於 → 「檢查更新」（只在 Android 顯示）。手動檢查不受 24 小時
  暫緩限制，並會顯示「已是最新版本」或錯誤訊息。
- **強制更新頁**：版本低於 BeeCount Cloud 後台的「最低可同步版本」時，整個 App 會被
  擋在強制更新頁（`lib/pages/license/force_update_page.dart`）。Android 在這頁多一顆
  「立即更新」，走同一套 R2 下載安裝流程；iOS 仍只有「我已更新，重新檢查」。

## version.json 格式

由發布腳本 `~/Downloads/build_apps_json.py --platform android` 產生：

```json
{
  "packageName": "com.tntlikely.beecount",
  "version": "3.6.0",
  "versionCode": 2,
  "releaseDate": "2026-09-26T08:00:00Z",
  "releaseNotes": "1. ...\n2. ...",
  "signingCertSha256": "a20a3e...",
  "apks": {
    "arm64-v8a": { "url": ".../beecount-3.6.0.apk", "size": 21953927, "sha256": "..." },
    "universal": { "url": ".../beecount-3.6.0-universal.apk", "size": 53040685, "sha256": "..." }
  }
}
```

- 比較的是 `version`（x.y.z），不是 `versionCode`。`versionCode` 只是寫給 Android
  安裝程式看的（必須遞增才能覆蓋安裝），腳本會自動遞增。
- `packageName` 跟目前安裝的不同就不提示：dev / debug 變體的 applicationId 帶
  `.dev` / `.debug` 後綴，裝了正式版 APK 會變成另一個 App，而不是升級。
- `signingCertSha256` App 端不使用，是給腳本比對「這次跟上一版是不是同一把金鑰」用的。

## 各檔案改動

- `lib/services/update/update_checker.dart`：整個改寫。移除 GitHub API、隨機
  User-Agent、release notes 清理這些 GitHub 專屬邏輯；改成讀 `kApkUpdateManifestUrl`
  （帶 `?t=` 時間戳避開快取）。判斷邏輯抽成純函式 `evaluateManifest` / `pickApk`，
  測試在 `test/services/update/update_checker_test.dart`。
  - ABI 選擇：用 `Platform.version` 裡的 `android_arm64` 判斷目前行程跑在 arm64 上
    就下載 arm64 主包（約 22 MB），其餘一律 universal（約 53 MB）。刻意不加
    `device_info_plus` 依賴（它目前只是 `flutter_cloud_sync` 的傳遞依賴）。
- `lib/services/update/update_result.dart`：新增 `sha256` 欄位。
- `lib/services/update/update_cache.dart`：新增 `matchesSha256`。
- `lib/services/system/update_service.dart`：
  - `downloadAndInstallUpdate` 新增 `expectedSha256`：快取的 APK 跟 version.json 的
    雜湊不符（同版本號重新打包過）就刪掉重下；下載完成後雜湊不符就刪檔並報錯，
    不會把不完整的檔案交給安裝程式。
  - `checkUpdateWithUI` 新增 `silent` 模式（啟動檢查用，任何失敗都不跳窗），
    `setLoading` / `setProgress` 改成可選。按「稍後」寫入 `ApkUpdateSnoozeStore`。
- `lib/services/update/apk_update_snooze_store.dart`（新）：「稍後」的 24 小時暫緩，
  逐版本失效。沒有做「此版本永不提示」——Android 版的使用者就是自己，永久關閉
  反而容易忘記更新；需要時手動檢查即可。
- `lib/services/update/update_downloader.dart`：GitHub 加速鏡像只套用在
  `github.com` 網址上（R2 網址加鏡像前綴會 404）；移除 GitHub Referer。
- `lib/services/update/update_dialogs.dart`：下載確認對話框移除鏡像選擇區塊，按鈕改
  「立即更新」；檢查失敗改為一般錯誤對話框；下載失敗的兜底按鈕從「前往 GitHub」
  （原作者的 repo）改成「用瀏覽器下載」（直接開 R2 的 APK 網址）。
- `lib/app.dart`：啟動提醒第 2 步依平台分流——Android 走
  `UpdateService.checkUpdateWithUI(silent: true)`，iOS 維持 `maybeShowAppUpdateReminder`。
  Android 不再呼叫 Cloud 的 `/app-version/latest`，避免同時跳兩種提醒。
- `lib/pages/settings/about_page.dart`：Android 才顯示「檢查更新」列。
- `lib/pages/license/force_update_page.dart`：改成 `ConsumerStatefulWidget`，Android 多
  一顆「立即更新」（主按鈕），「重新檢查」降為次要按鈕。這頁會取代整個首頁，`app.dart`
  的啟動自動檢查跑不到，沒有這顆按鈕的話被擋住的 Android 使用者只能自己去找 APK。
- l10n：新增 `updateNowButton` / `updateOpenInBrowser` / `updateChecksumMismatch` /
  `updateNotApplicableBuild` / `aboutCheckUpdateSubtitle`（只維護 en + zh_TW）。

- `android/settings.gradle`：Kotlin Gradle plugin 2.2.0 → 2.2.20。跟這個功能無關，
  是 Flutter 3.47 要求的最低版本，不升級 `flutter build apk` 會直接失敗。

原生端不用改：`AndroidManifest.xml` 早已宣告 `REQUEST_INSTALL_PACKAGES` + FileProvider，
`MainActivity.kt` 的 `com.tntlikely.beecount/install` channel 也已存在。

## 發布腳本（`~/Downloads/build_apps_json.py`）

新增 `--platform {ios,android,all}`，預設 `all`。可在 Finder 雙擊同資料夾的
`發布BeeCount.command` 執行，輸出會寫在腳本所在的資料夾。iOS 維持原行為：不會自動
Archive，而是抓 Xcode 最新的 `.xcarchive` 打包 IPA；版本號跟 pubspec 不同時只提醒、
不中止。兩個平台互相獨立，iOS 找不到 Archive 時 Android 照樣完成，最後以非 0 結束
並列出沒完成的平台。Android 模式：

1. 檢查 `android/key.properties` 與它指向的金鑰檔存在；沒有就中止。原因是
   `build.gradle` 在沒有 key.properties 時會自動改用臨時的 `ci-debug.keystore`
   簽章，那樣發出去的 APK 之後就再也無法用正式金鑰覆蓋升級。
2. versionCode = max(pubspec 的 `+N`, 上一版 version.json 的 versionCode + 1)。
   上一版優先讀目前目錄的 version.json，沒有就用 `curl` 去 R2 抓線上那份（macOS
   上 python.org 版 Python 常缺根憑證，urllib 會 SSL 失敗）。只有線上明確回 404 才當
   第一次發布；其他錯誤一律中止，免得在不知情的情況下跳過第 4 步的簽章比對。
3. `flutter build apk --flavor prod --release --build-number=<N>`。
4. 用 `aapt` 驗證 packageName / 版本號，用 `apksigner` 取簽章憑證 SHA-256，跟上一版
   不同就中止（`--allow-signer-change` 才放行）。
5. 複製成 `beecount-<ver>.apk`（arm64）/ `beecount-<ver>-universal.apk`。App 端快取
   依檔名 `beecount-x.y.z.apk` 找已下載的舊檔，所以主包檔名格式不能改。
6. 寫出 `version.json`，列出上傳清單，**version.json 排最後**：先傳 APK 再傳描述檔，
   才不會有使用者讀到新描述檔卻下載不到 APK 的空窗。

## 跟 BeeCount Cloud 後台「App 版本更新提醒」頁的關係

- 「目前最新版本號」與 NAS WebDAV 自動偵測：Android 不再讀取，只影響 iOS 的提醒。
  Android 的最新版本以 R2 的 `version.json` 為準。
- 「最低可同步版本」：Android 照樣生效。調高之前要先把新版 APK 和 `version.json` 傳到
  R2，否則被擋住的 Android 使用者按「立即更新」只會看到「已是最新版本」。

## 刻意不做 / 已知限制

- 第一次：目前手機上的舊版 APK 沒有這個功能，要手動裝一次含此功能的版本，之後
  才會自動收到更新。
- 不上 Google Play：Play 政策限制 `REQUEST_INSTALL_PACKAGES` 與 App 自我更新。
- `GitHubMirrorService` 與鏡像選擇對話框 (`showMirrorSelectDialog`) 目前沒有入口，
  只在下載網址是 GitHub 時才會用到，暫時保留沒刪。
- 沒有「強制更新」或最低支援版本。
