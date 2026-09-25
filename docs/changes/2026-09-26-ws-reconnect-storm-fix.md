# 2026-09-26 WebSocket 重連風暴修正（App + BeeCount Cloud Web）

## 事故

2026-09-25 07:00 起，Cloudflare 看到 `beecount-dev` 24 小時內有 1.88M 次請求，但只有 37 個訪客：

- `/ws` 74.4 萬次、`/api/v1/sync/pull` 74.9 萬次，兩者幾乎 1:1
- User-Agent：Mac Chrome 1.83M（**Cloud Web 面板**）、`Dart/io` 4.8 萬（App）
- 2xx 1.12M、4xx 只有 16k，代表 pull 本身都成功，不是授權 402 迴圈
- `/auth/refresh` 3.9 萬次、`/profile/me`、`/read/ledgers` 各約 4〜5 萬次

主要元兇是 Web 端，App 端只是跟著放大。

## 根因

### Web：`useSyncSocket` 洩漏殭屍連線（主因）

檔案：`BeeCount-Cloud/frontend/apps/web/src/hooks/useSyncSocket.ts`

1. `connect()` 會先 `await ensureFreshToken(token)`。token 快過期時會 refresh → `setToken` → effect 以新 token 重跑。
2. 舊的 `destroyedRef` 是**跨 effect run 共用的 ref**：舊 run 的 cleanup 設成 `true`，新 run 馬上又改回 `false`。舊 run 的 await 結束後看到 `false`，照樣 `new WebSocket(...)`。
3. teardown 只會關 `socketRef.current`，所以舊 run 開出的那條**永遠不會被關掉**（連 unmount 後都還開著，已在瀏覽器裡用舊版程式碼重現）。
4. 殭屍 chain 手上拿的是舊的過期 token，每次重連都會再 refresh 一次 → 再觸發一次 effect 重跑 → 可能又多一條殭屍。這是正回饋。
5. 超過 server `WSConnectionManager.MAX_CONNECTIONS_PER_USER = 5` 之後，server 會踢掉最舊的一條（close 4001）。被踢的那條之前在 `onopen` 已經把退避歸零，所以 500ms 內就會重連，接著又擠掉另一條，變成無限互踢。每次 `onopen` 都會 `drainPull`，所以 ws:pull 剛好 1:1。

另外兩個次要漏洞也一起修掉：心跳逾時會自己排一次重連，接著 `onclose` 又排一次，重連 chain 因此變成兩倍。`online`/`visibilitychange` 在 socket 還在 CONNECTING 時也會再開一條。

### App：固定 3 秒重連、沒有退避

檔案：`packages/flutter_cloud_sync/lib/src/providers/beecount_cloud_provider.dart`（`BeeCountCloudRealtimeClient`）

一般斷線都固定 3 秒重連，被 4001 踢掉也一樣。每次連上都會發出 `connected` 事件，`SyncEngine` 收到後會跑一次完整 auto sync（`syncLedgersFromServer` + 共享資源對帳 + push/pull，見 `lib/cloud/sync/sync_engine_realtime.dart` 的 `_scheduleAutoSync`）。只要跟 Web 殭屍連線搶名額，一台裝置一天最多就會多打約 2.9 萬輪。

## 修正

### Web `useSyncSocket.ts`

- socket、計時器、退避次數、`disposed` 旗標全部改成**每次 effect run 各自一份的區域變數**，不再使用共用 ref。舊 run 被 dispose 後，不可能再開出連線。
- 每個 socket handler 都會檢查 `socket === next`，只處理自己追蹤的那條。主動關閉（心跳逾時、cleanup）時先拔掉 handler 再 `close()`，避免重連被排兩次。
- `scheduleReconnect` 會先清掉舊 timer；`connect()` 以 `connecting || socket` 防止重入。
- 退避改成連線**穩定 30 秒**才歸零（`STABLE_CONNECTION_MS`），不再是一 `onopen` 就歸零。
- 收到 close 4001 時至少等 60 秒才重連（`EVICTED_RECONNECT_MS`）。

驗證方式：在 Vite dev server 頁面中動態載入真正的 hook 模組，換上假 WebSocket：
- 舊版：refresh race 開出 2 條 socket，unmount 後仍有 1 條開著
- 新版：只開 1 條；連上又立刻斷時，重連間隔會遞增（550ms → 1483ms…）；4001 排程 60000ms

### App `BeeCountCloudRealtimeClient`

- 重連改成指數退避：3s 起跳，每次加倍，上限 60s，另加 0〜1s jitter。連線穩定 30s 才歸零。
- 4001（被踢）和既有的 4402/4426（授權、版本門檻）一樣，至少等 60s。

## 刻意不做的事

- **Server 端 `MAX_CONNECTIONS_PER_USER` / 踢最舊的策略不動**：這是 2026-08-15 為了防止殭屍連線堆積加上的保護，本身沒有錯。問題出在 client 被踢後會立刻反撲。
- Web 的 `onOpen → drainPull` 不另外加節流：修正後只有真正的新連線才會觸發，頻率已經受退避限制。

## 上線注意

殭屍連線活在**已經開著的瀏覽器分頁**裡。部署新版前端後，必須重新整理或關掉所有開著 `beecount-dev` 的分頁，舊的迴圈才會停。只部署、不重整的話，流量不會降下來。
