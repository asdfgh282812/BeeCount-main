# 專案圖示 emoji 兜底渲染 (2026-09-07)

## 背景

使用者回報：在 Web/BeeCount Cloud 面板為專案（`Project`）設定了圖示，但同步到 App 後看起來「沒有同步過來」。

排查後確認 `Projects.icon` 欄位本身在同步鏈路上是完整的：
- 推送：`entity_serializer.dart:505` `serializeProject` 無條件帶上 `icon`
- 拉取：`sync_engine_apply.dart` 的 `_applyProjectChange` 有正確寫回 `Projects.icon`（insert/update 都有）
- Cloud 端 schema、merge-spec、snapshot 也都有這個欄位

真正的問題是**兩端對 `icon` 字串的語意不一致**：
- Web 端 `ProjectsPanel.tsx` 的圖示欄位是純文字輸入框，使用者可以直接打 emoji（例如 `📁`），渲染時也是把字串當文字直接印出來
- App 端 `project.icon` 一律丟給 `CategoryService.getCategoryIcon()`，這是一個只認識固定 Material icon 名稱字串（如 `'restaurant'`）的 `switch`，對不認識的字串會靜默 fallback 成 `Icons.category`

所以資料其實已經同步下來，只是 App 把 emoji 字串當成「不認識的 icon name」直接吃掉、顯示成通用圖示——看起來像沒同步。

## 修改內容

### `lib/services/data/category_service.dart` — 新增共用兜底渲染

新增 `CategoryService.looksLikeEmoji(String)` 與 `CategoryService.iconOrEmojiWidget({icon, color, size})`：字串「看起來像 emoji」（≤4 字元且首個 code point 落在 ASCII 之外很遠的區域）就直接畫 `Text`，否則照舊丟給 `getCategoryIcon` 走 Material icon 渲染。

這個啟發式跟 `lib/widget/views/widget_view_style.dart` 裡桌面小組件既有的 `widgetLooksLikeEmoji`/`widgetCategoryIcon`（服務分類圖示的同類問題）是同一套算法，只是那邊是桌面 widget 系統私有實作、這裡是主 App 開的公開版本，兩邊不互相呼叫。

### 套用到專案圖示的所有渲染點

改用 `CategoryService.iconOrEmojiWidget` 取代原本的 `Icon(CategoryService.getCategoryIcon(project.icon), ...)`：

- `lib/pages/project/project_overview_page.dart` — 專案清單卡片
- `lib/pages/project/project_detail_page.dart` — 專案詳情頁頂部
- `lib/pages/project/project_edit_page.dart` — 編輯頁的圖示預覽（`_selectedIcon` 若是從 Web 建立的專案帶進來的 emoji，這裡也一併吃到）
- `lib/widgets/biz/project_picker.dart` — 記帳時挑選專案的彈窗（`_ProjectRow.icon` 欄位型別從 `IconData` 改成 `Widget`，讓呼叫端可以塞 emoji `Text` 或一般 `Icon`）
- `lib/widgets/biz/transaction_detail_card.dart` — 交易詳情卡片裡的專案列（連帶把 `_detailItem` 的 `icon` 參數型別也改成 `Widget`，新增 `_tertiaryIcon` 小工具把既有的純 `IconData` 呼叫點包一層，維持原本外觀不變）

## 不在此次範圍

- 沒有改 Web/BeeCount Cloud 端：`ProjectsPanel.tsx` 的圖示欄位仍然是自由文字輸入，不會強制使用者選 Material icon 名稱。若之後想讓兩端輸入體驗完全一致（例如 Web 也换成跟 App 一樣的圖示選擇器），需要跨 repo 改動，這裡先只在 App 端做「認得出 emoji 就直接顯示」的相容處理。
- 分類（`Category`）圖示不受影響，本來就只允許透過 App 的 `GroupedIconGrid`/`icon_picker_page.dart` 選 Material icon 名稱，沒有 Web 自由輸入 emoji 的情境。
