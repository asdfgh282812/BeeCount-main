# 交易列表項目：標籤換行 + 顯示專案

## 背景

首頁日曆的每日交易列表（`CalendarBody`）中，`TransactionListItem` 原本把標籤
chip（含 `tag_seed_service.dart` 自動建立的「拍照記帳」「AI記帳」等來源標籤）
塞進金額欄下方一個寬度被金額文字撐開的窄 `Row` 裡。標籤一多，這個 `Row` 的
intrinsic 寬度會擠壓左側 `Expanded` 的分類名/備註/時間欄，造成畫面擁擠甚至視覺
重疊；同時列表項目完全沒有顯示交易關聯的專案（`Projects` / `projectSyncId`）。

## 改動

### `lib/widgets/biz/transaction_list_item.dart`
- 新增 `db.Project? project` 欄位。
- 金額欄下方原本的標籤 `TagChipList` 改為顯示**專案 pill**（`_buildProjectChip`，
  樣式比照既有的 `ledgerName` pill：主題色 10% 底色 + 圓角）。因為一筆交易最多
  只能關聯一個專案，不需要換行/省略邏輯，沿用原本標籤所在的位置。
- 標籤改為在整張卡片下方**獨立佔一整列**（`Padding(left: 44)` 對齊分類圖示右側
  文字起點），並移除 `TagChipList` 的 `maxDisplay` 截斷（改成
  `tags!.length`），讓 `TagChipList` 內建的 `Wrap` 在標籤多時自然換到下一行，
  不再擠壓其他內容或依賴「+N」堆疊。
- 這是共用元件，因此標籤換行的版面調整對所有呼叫方（分類明細、搜尋、日曆、
  專案明細、標籤明細等頁面）都生效；`project` 欄位預設為 `null`，其他呼叫方
  不受影響（沒有顯示專案的行為變化）。

### 資料串接（僅首頁日曆列表）
專案透過 `Transactions.projectSyncId`（字串，非本地 int FK）關聯，之前只有
`transaction_detail_card.dart` 會單獨查詢。這次讓日曆的每日列表也能拿到專案：
- `lib/data/repositories/transaction_repository.dart`、
  `lib/data/repositories/local/local_repository.dart`：
  `getTransactionsByDate` / `getTransactionsByDateRange` 回傳的 record type
  新增 `Project? project` 欄位。
- `lib/data/repositories/local/local_transaction_repository.dart`：
  - `getTransactionsByDate`：新增依 `projectSyncId` 批次查 `Projects` 表
    （避免 N+1）。
  - `getTransactionsByDateRange`：目前程式庫內沒有任何呼叫方在用這個方法
    （逐筆查詢的舊實作），為了滿足 record type 一致仍補上逐筆查詢的專案欄位。
  - `_hydrateSharedOverridesFull`（`getTransactionsByDate` /
    `getTransactionsByDateRange` 共用的收尾 hydration helper）的 input/output
    record type 都補上 `project` 並在重組時透傳（`project: r.project`），沒有
    對應的共享帳本 hydration 邏輯（專案目前不支援共享帳本鏡像）。
- `lib/providers/calendar_providers.dart`：`transactionsByDateProvider` 的
  record type 同步補上 `Project? project`。
- `lib/pages/calendar/calendar_body.dart`：建構 `TransactionListItem` 時多傳
  `project: item.project`。

## 刻意排除的範圍
- 只在首頁日曆列表（`calendar_body.dart`）串接了專案資料。`transaction_list.dart`
  （「明細」全列表頁）目前仍不顯示專案，因為那邊的資料流是另一套（見
  `transaction_list.dart` 的 `_getTagsForTransaction()` / 批次查詢），需要另外
  串接，範圍留到之後有需要再做。
- 專案 pill 沒有點擊互動（`onProjectTap`）——現有 `ledgerName` pill 也沒有，先
  維持一致，不過度設計。
- 沒有更動「拍照記帳」「AI記帳」等來源標籤的產生方式（仍是
  `tag_seed_service.dart` 自動建立的一般標籤），只是它們現在跟其他標籤一起換
  行顯示。

## 驗證
`flutter analyze` 全專案通過（僅既有、與本次改動無關的 lint info/warning）。
因環境的 iOS Simulator 工具卡在 `xcode-select` 未設定（需要使用者用 sudo 執行
`xcode-select -s /Applications/Xcode.app/Contents/Developer`），這次沒有做到
實機/模擬器畫面驗證，建議之後手動用 `flutter run --flavor dev` 檢查首頁日曆列
表在多標籤 + 有專案情境下的實際排版。
