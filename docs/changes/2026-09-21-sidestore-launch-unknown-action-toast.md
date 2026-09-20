# 修正從 SideStore 啟動 App 會彈「未知的操作:」toast

## 症狀

從 SideStore（或 AltStore）點「打開」啟動 BeeCount 時，App 開起來後畫面中央會浮出一個
toast：`未知的操作:`（冒號後面是空的）。功能沒壞，但每次側載啟動都會出現，很像 bug。

## 原因

側載商店不是用一般的 launch services 開 App，而是直接開 App 自己註冊的 URL scheme
（`ios/Runner/Info.plist` 的 `CFBundleURLSchemes` = `beecount`），也就是送一條
`beecount://` 進來。這條 URL 沒有 host、沒有 path、沒有 query——它只表達「把 App 拉
起來」，不帶任何動作。

`app_links` 的 `uriLinkStream` 照樣把它投遞給 `lib/main.dart` 的 `_setupUrlListener`，
於是走進 `AppLinkService.parseAction`：`uri.host` 是空字串，`switch` 落到 `default`
→ `AppLinkAction.unknown` → `handleUrl` 回 `AppLinkResult.failure('未知的操作: ${uri.host}')`。
`main.dart` 的 `dispatch()` 對任何 `!result.success` 都會彈 toast，而 host 是空的，
所以訊息就長成「未知的操作:」後面什麼都沒有。

## 改動

`lib/services/platform/app_link_service.dart`：

- 新增 `AppLinkAction.launch`，代表「純啟動連結」。
- `parseAction` 在 `switch` 之前先判斷：`host` 為空且 `path` 為空或 `/` → `launch`。
  之所以連 `path` 一起判斷，是為了不把 `beecount:something` 這種畸形連結也吞掉——
  那種還是應該落到 `unknown`。
- `handleUrl` 的 `launch` case 回 `AppLinkResult.success()`（message 為 null）。
  `dispatch()` 只在 `!success` 時彈 toast，成功且無 message 就完全靜默，只留一行
  info log 方便日後查。

`test/services/app_link_parse_action_test.dart`（新增）：覆蓋 `beecount://` /
`beecount:///` → `launch`、已知 host 不受影響、無法辨識的 host 仍是 `unknown`。

## 刻意不做

- **沒有改 `dispatch()` 的 toast 策略**（例如「host 為空就不彈」）。失敗要讓使用者看到
  原因，這是正確的；問題出在「純啟動」根本不該被歸類成失敗，所以修在 `parseAction`
  這層語意最準，也不會順手弱化其他錯誤的可見度。
- **`lib/app.dart` 的 `_openDeepLink` 沒有加 `launch` case**：那個 switch 本來就有
  `default: break`，而且 `launch` 不會呼叫 `onNavigate`，`pendingAppLinkActionProvider`
  永遠不會被設成 `launch`，不需要額外處理。
- Android 沒有對應問題（側載不透過 URL scheme 啟動），但這個修正是平台無關的。

## 入口

無使用者可見的新入口——這是純修 bug，使用者感受到的變化就是從 SideStore 啟動不再彈
那個 toast。
