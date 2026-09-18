# 修正編輯帳戶的初始資金不會立刻反映，直到下一筆交易才「補加」的問題

## 問題

已建立的帳戶（尤其是投資理財等純記錄型帳戶）若在「編輯帳戶」頁把初始資金改成非零值後儲存，帳戶頁的「調整總額」對話框仍顯示編輯前的舊「目前�餘額」（例如改成 300 後仍顯示 NT$0.00）。

如果使用者接著用「調整總額」把餘額調整到某個目標值（例如 6000），因為對話框算的差額是「目標 − 畫面上的舊餘額」，實際寫入的調整交易金額會是 6000（而不是 6000 − 300 = 5700）。等這筆調整交易觸發統計重新整理後，真正的餘額才第一次被正確計算出來：`initialBalance(300) + 調整交易(6000) = 6300`，讓使用者感覺剛剛存的初始資金「憑空多加了一次」。

## 原因

帳戶餘額（`initialBalance` + 交易加總）由 `accountStatsProvider`（[statistics_providers.dart:86](../../lib/providers/statistics_providers.dart)）計算，並用 `ref.keepAlive()` 快取，只有在它 watch 的 `statsRefreshProvider` tick 改變時才會重新計算。

新增/編輯交易後會走 `PostProcessor.run`，會 bump 這個 tick；但帳戶新增/編輯走的是 `PostProcessor.sync`（[account_edit_page.dart:1498](../../lib/pages/account/account_edit_page.dart)），依 `PostProcessor` 類別自己的分類註解，`sync` 系列本來就設計成「僅同步、不刷新統計」，用於分類/帳戶等異動。這個假設對帳戶的其他欄位（改名、換圖示…）成立，但對 `initialBalance` 不成立——它本身就是餘額公式的一部分。

於是編輯帳戶把 `initialBalance` 寫進 Drift 後，`accountStatsProvider` 快取沒被 invalidate，`調整總額` 對話框（[account_quick_actions.dart](../../lib/utils/account_quick_actions.dart) `showBalanceAdjustmentDialog`）用 `ref.read(accountStatsProvider(id).future)` 讀到的還是編輯前算好的舊值，`目前餘額` 顯示錯誤，差額也算錯。餘額公式本身（`local_account_repository.dart` 的 `getAccountBalance`）沒有問題，每次被觸發計算時都是重新從 DB 讀 `initialBalance` 現算，純粹是「編輯後沒有 invalidate 快取」的問題。

## 修復

在 `_save()`（[account_edit_page.dart:1341](../../lib/pages/account/account_edit_page.dart)）建立/更新帳戶成功後、觸發同步之前，補上 `ref.read(statsRefreshProvider.notifier).state++`，讓 `accountStatsProvider`、`allAccountStatsProvider`、`allAccountsTotalStatsProvider`、淨資產相關 Provider 這批依賴同一個 tick 的統計快取一起重新計算，涵蓋新增帳戶（含非零初始資金立刻反映到淨資產）與編輯帳戶（含改初始資金）兩種情境。

沒有改動 `PostProcessor.sync` 本身的語義（仍維持「其他資料異動只同步」的既有分類），只在帳戶頁自己多 bump 一次統計 tick，成本是每次存帳戶都多算一次（本就很輕量的）帳戶統計查詢。
