# 修正:refresh session 失败时误清除本地登入状态

## 问题

使用者反馈:App 端应该跟网页端不同 — 网页每次开启都是全新页面,理论上需要重新登入是预期行为;但 App 端本地持久化了 session,不应该无故自动登出,而是应该一直保持登入状态。实测发现 App 偶尔会在没有使用者操作的情况下回到未登入画面。

## 根因

`packages/flutter_cloud_sync/lib/src/providers/beecount_cloud_provider.dart` 的 `BeeCountCloudAuthService`:

- `_refreshSession()`(原 1925-1944 行)对 `/auth/refresh` 的任何非 2xx 响应都统一抛 `CloudAuthException`,不区分「refresh token 真的被 server 拒绝(401/403)」和「其它瞬时故障(5xx、限流等)」。
- `_doRefreshSession()`(原 1449-1457 行)的 `catch (_)` 把 `_refreshSession()` 抛出的**任何**异常 —— 包括底层 `_httpClient.send()` 的网络层异常(断线、超时、DNS 失败等)—— 都当成「refresh token 已失效」处理,直接调用 `_clearSession()` 清空 `SharedPreferences` 里的本地 session 并对外发出 `authStateChanges(null)`。

`_clearSession()` 是全局唯一会让 App 判定「已登出」的地方(见 `lib/app.dart`、`cloud_sync_page.dart` 等对 `authStateChanges`/`currentUser` 的订阅)。也就是说:只要背景刷新 token 时恰好遇到一次网络抖动或 server 502,App 就会把使用者静默登出,即使 refresh token 在 server 端从未真的失效。

## 修正

- `_refreshSession()`:只有 401/403(server 明确拒绝 refresh token)才抛 `CloudAuthException`;其余非 2xx(5xx、429 等)改抛 `CloudStorageException`,标记为「请求失败但不代表 token 失效」。
- `_doRefreshSession()`:只在捕获到 `CloudAuthException` 时才调用 `_clearSession()`;其它异常(网络层异常、`CloudStorageException`)仅返回 `false`,保留本地已存的 session,让下一次同步/刷新再重试。

## 影响范围

- `currentUser` / `requireAccessToken()` 在这次 refresh 失败时仍会走既有的「凭证兜底重登」分支(逻辑未变),但只有在 server 明确拒绝 refresh token 时,`authStateChanges` 才会翻成已登出、本地 session 才会被清掉。瞬时网络/服务端故障不再造成使用者被静默登出,下次网络恢复后台刷新即可继续使用已登入状态。
- 未改动真正的登出入口(`cloud_sync_page.dart`、`cloud_service_page.dart` 里使用者主动点击的登出按钮),该行为不受影响。

## Out of scope

- Server 端 refresh token 的过期时间 / rotation 策略在 BeeCount-Cloud(独立仓库)里,本次未涉及。
- 网页端(BeeCount-Cloud web panel)是否要改成同样「不自动登出」的行为不在本次范围内 —— 目前网页本来就没有本地持久化 session,重新整理即视为新会话,是预期设计,不是 bug。
