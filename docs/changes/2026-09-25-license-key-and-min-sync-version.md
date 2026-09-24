# 授權金鑰 + 最低可同步版本（App 端）

> 跨 repo 變更。Server 端設計、強制點、API、上線順序見 `BeeCount-Cloud/docs/LICENSE_KEYS.md`，這裡只記 App 端。

## 需求

1. Server 後台「App 版本更新提醒」頁可設定**最低可同步版本**，低於此版本的 App 無法同步。
2. 新版 App 若低於此版本，整個 App 擋住強制更新；舊版 App（沒有這次改動）只會同步失敗。
3. 授權金鑰：所有使用者（管理員除外）都要輸入金鑰才能使用。金鑰存在 server，綁帳號、啟用後一年；App 向 server 取得授權，本地可離線使用 7 天，每次連網確認有效就再延長 7 天，超過 7 天沒連網就整個擋住。

使用者確認的決策：只有一台 server（本人架設）、管理員免金鑰、**所有 App 使用者都必須登入 BeeCount Cloud**（本機 / iCloud / WebDAV / S3 / Supabase 模式的使用者也一樣，授權一定要跟 server 驗證）、金鑰綁帳號從啟用當天起算一年。

## 入口

- 沒有授權時：啟動後直接出現全螢幕授權頁（無法進入任何功能）。
- 新使用者：歡迎頁「伺服器位址 → SSO 登入」之後，帳號沒有授權會多一頁「輸入授權金鑰」。
- 查看到期日 / 輸入新金鑰延長：**我的 → 授權金鑰**（「資料管理」下方）。
- 版本過舊：啟動後直接出現「請更新 App」頁。

## 改動

### `packages/flutter_cloud_sync`

- `src/providers/beecount_cloud_gate.dart`（新）：
  - `BeeCountCloudGateHttpClient` 包住 auth / storage service 的 `http.Client`，**每個請求**補 `X-App-Version`，收到 402 / 426 時呼叫 `BeeCountCloudClientGate.onLicenseRequired` / `onAppVersionTooOld`。集中在 HTTP 層，不必每個呼叫點各自判斷。
  - 版本值用 `PackageInfo.version`（不含 build number），由 `main.dart` 在第一個請求之前設定。
- `beecount_cloud_provider.dart`：
  - auth / storage 兩個 service 的 `_httpClient` 改用上面的包裝（外部傳入的 client 也會被包起來）。
  - 新增 `fetchLicenseStatus()` / `activateLicense(key)`、`BeeCountCloudLicenseStatus`、`BeeCountCloudLicenseException`（帶 server `error.code`）、`_extractErrorCode`。
  - `BeeCountCloudLatestAppVersion` 多 `minSyncVersion`。
  - WebSocket URI 多帶 `?app_version=`（握手不能帶自訂 header）；server 以 4402 / 4426 關閉時通知 App 層，重連間隔拉長到 60 秒（避免被擋時每 3 秒重連一次）。

### `lib/providers/license_providers.dart`（新）

- `licenseGateProvider`（`LicenseGateNotifier`）：狀態 `checking / valid / needsLogin / needsKey / needsNetwork`。
  - 啟動、回到前景（60 秒節流）、BeeCount Cloud provider / auth provider 重建、任何 API 回 402 時都會 `refresh()`；同時間只跑一個請求。
  - 本地快取有效就**先放行**（不讓使用者等網路），再連線確認。server 說沒授權 → 立刻清快取、擋住；連不上 → 看本地快取；未登入 → needsLogin。
  - App 一直開在前景時，到本地期限那一刻（最多每 6 小時）也會重新確認，所以 server 端撤銷金鑰在前景也會生效。
  - 冷啟動時先 `await activeCloudConfigProvider.future` 再取 `beecountCloudProviderInstance`，否則設定還沒載入時第一輪會拿到 null，被誤判成「沒設定 BeeCount Cloud」。
- `appVersionGateProvider`（`AppVersionGateNotifier`）：從公開 `GET /app-version/latest` 取 `min_sync_version`，存 SharedPreferences（`beecount_min_sync_version_cache`），**離線時用上次的門檻照樣擋**。任何 API 回 426 時重查。版本比較規則跟 server `services/license.py::parse_version` 相同（`3.6.0+2` 取 `3.6.0`，缺的段補 0）。

### `lib/services/license/license_cache.dart`（新）

本地授權快取（SharedPreferences `beecount_license_cache_v1`）：

- 綁 server + userId，換帳號 / 換 server 就失效。
- 可離線期限 = 確認當下 + min(7 天, 金鑰到期日 − **server 當下時間**)，用 server 時間換算剩餘天數，裝置時鐘跟 server 有誤差也不會多給。
- 防時鐘回撥：記錄看過的最大裝置時間，時間比它早超過 10 分鐘就視為被調過，快取失效（必須連網）。
- **刻意沒做的**：沒有用加密 / 簽章保護快取。root / 越獄後直接改 SharedPreferences 可以延長本地可用期限，但只影響「本機」使用 —— 雲端資料的每個請求 server 都會再檢查授權，改本地快取拿不到任何雲端資料。在 App 端做簽章的效益不大（攻擊者一樣可以改 App 本身）。

### `lib/services/license/beecount_cloud_server_setup.dart`（新）

把歡迎頁原本私有的「探測 server + 確認 SSO + 存檔 + 切換同步後端」抽成 `configureBeeCountCloudServer()`，歡迎頁與授權頁共用一份。

### 畫面

- `lib/pages/license/license_gate_page.dart`：全螢幕授權頁（樣式同歡迎頁）。needsLogin 時先問伺服器位址（已是 BeeCount Cloud 模式就直接顯示登入），再內嵌既有 `AuthPage` 做 SSO；needsKey 顯示金鑰表單（已過期會顯示到期日）+「登出並切換帳號」；needsNetwork 顯示重試。
- `lib/pages/license/license_key_form.dart`：金鑰輸入表單，三處共用；server 錯誤碼對應到中文訊息。
- `lib/pages/license/force_update_page.dart`：強制更新頁。**不放下載連結** —— 安裝管道不只一種（App Store / TestFlight / SideStore / APK），請使用者從原本的管道更新。
- `lib/pages/license/license_settings_page.dart`：我的 → 授權金鑰。
- `lib/pages/auth/welcome_page.dart`：SSO 登入後先確認授權，沒有就插入金鑰頁，啟用後才繼續原本的「拉帳本 → 貨幣 / 分類」流程（server 對沒授權的帳號所有資料 API 都回 402，不先確認的話拉帳本會失敗）。

### `lib/main.dart`

- 啟動時設定 `BeeCountCloudClientGate.appVersion` 與 402 / 426 回呼。
- `_getHomePage` 順序：**版本過舊 → ForceUpdatePage**（連歡迎引導都不進）→ 歡迎頁 → Splash → **授權無效 → LicenseGatePage** → App 鎖 → BeeApp。
- 授權失效 / 版本被擋時 `popUntil(isFirst)`，把 push 在 home 之上的子頁面收掉，否則停在設定頁的使用者看不到授權頁。

## 舊版 App 會怎樣（需求 2 的確認結果）

舊版 App 不送 `X-App-Version`，server 一律視為過舊 → 所有 API 回 426。舊版 App 的 `SyncEngine.sync()` 會吞掉例外，使用者看到的是：「我的」頁同步狀態「狀態取得失敗」、帳本卡片紅色雲朵，BeeCount Cloud 同步頁的健康檢查會顯示 server 回傳的訊息「App version too old: 請將 App 更新到 X 以上版本才能同步」。不會閃退、不會刪資料。

**限制**：舊版 App 沒有授權門，本機記帳功能仍可使用，只是完全無法同步 —— 已安裝的舊程式無法被遠端改變。所以新版上架後要盡快在後台把「最低可同步版本」設成新版本號。

## 測試

- `test/services/license/license_cache_test.dart`：離線 7 天、不超過金鑰到期、用 server 時間換算、綁 server/帳號、時鐘回撥、版本比較。
- `packages/flutter_cloud_sync/test/beecount_cloud_gate_test.dart`：header 注入、402/426/WS close code 回呼、JSON 解析。
- Server 端：`BeeCount-Cloud/tests/test_license_keys.py`、`tests/test_license_route_audit.py`。
