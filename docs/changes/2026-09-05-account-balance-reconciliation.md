# 帳戶餘額主動比對修正（reconcileAccountBalances）

## 背景 / 根因

使用者回報：BeeCount Cloud 伺服器端「投資理財」分類下兩個帳戶（投資帳戶本金、AIFAN本金）金額正常，但 App 端「資產管理」頁面顯示為 0。

追查後確認兩處餘額顯示其實共用同一個計算入口 —— `LocalAccountRepository.getAccountBalance()`（[lib/data/repositories/local/local_account_repository.dart:414](../../lib/data/repositories/local/local_account_repository.dart)），對估值型帳戶（`investment` 屬於 `isValuationOnlyType`）直接回傳 `Accounts.initialBalance` 欄位本身，不看交易紀錄。所以問題精確收斂為：本機資料庫這個欄位的值本身是 0。

根因在 `lib/cloud/sync/sync_engine_apply.dart` 的 `_applyAccountChange`：

- Web 端 PATCH 帳戶用 `exclude_unset=True`，廣播給其它裝置的 `SyncChange.payload` 只含使用者實際改動的欄位，不是全量快照。
- **update 分支**（本機已有這筆帳戶）對每個欄位都有 `containsKey` 保護，缺鍵就 `d.Value.absent()` 不覆蓋本地值 —— 安全。
- **insert 分支**（本機第一次見到這個 syncId）**沒有同樣保護**：`initialBalance`/`type`/`currency` 缺鍵時會落地成硬編碼預設值 `0.0`/`'cash'`/`'CNY'`。

若這台裝置對某帳戶套用的第一筆變更事件，剛好是一次局部 PATCH（例如只改了 `parentAccountId` 做帳戶分組）而非攜帶完整欄位的建帳事件，就會把預設值當真實資料寫死；此後除非再等到一次「含完整欄位」的 update 事件，這個錯誤值會一直卡住（後續局部 update 只會 `absent()` 保留現值，不會再糾正）。這跟同一段程式碼註解裡提到的歷史事故（"信用卡群组子卡被冲成现金+人民币"）是同一類坑，只是這次踩在 `initialBalance` 上。

`SyncChange.action` 欄位（App 端與 BeeCount-Cloud 伺服器端）全程只有 `'upsert'`/`'delete'` 兩種值，沒有第三種訊號能可靠區分「這是首次建立」還是「局部欄位更新」，所以無法單靠 `action` 判斷來防呆；insert 路徑本身也沒有現成的「單一帳戶完整快照拉取」機制可用（唯一相關的 `readAccounts()` 之前在 `lib/cloud/sync/` 完全沒有被呼叫）。

## 解法：偵測並修正，而非事前預防

沒有直接修 `_applyAccountChange` insert 分支本身（風險：該分支 containsKey 邏輯已經很密集，牽動多個欄位語意，且無法可靠分辨「首次建立」情境）。改為新增一個「主動比對＋自動修正」機制，較符合使用者需求（「app 自己與 server 比對，如果金額不同的話，就應該要嘗試重新同步至一樣」），也能自癒任何同類根因造成的髒資料：

- 新增 `SyncEngineHealthChecks.reconcileAccountBalances({required int ledgerId})`（[lib/cloud/sync/sync_engine_status.dart](../../lib/cloud/sync/sync_engine_status.dart)）：呼叫既有但先前未接線的 `provider.readAccounts(ledgerId:)`（user-global 全量快照讀取，不受 `exclude_unset` 影響，含完整 `initialBalance`/`accountType`/`currency`），逐一比對本機 `Accounts` 表對應 syncId 的這三個欄位，不一致就直接以 server 為準覆寫本地（不經 `ChangeTracker`，因為這是把本地拉齊到 server 已知狀態，不是產生新的本地改動去 push，否則會造成推送環路）。回傳修正筆數。
- 在 `lib/pages/cloud/beecount_cloud_sync_page.dart` 的 `_onRefresh()`（下拉刷新流程）裡，緊接著既有的 `checkSyncHealth`（只做筆數比對）之後呼叫這個新方法；若有修正，用 `showToast` 提示使用者「已修正 N 個與伺服器不同步的帳戶」（新 l10n key `accountBalanceReconciled`，僅加入 `app_en.arb`/`app_zh_TW.arb`，依照專案慣例不維護 `app_zh.arb`/`app_ko.arb`）。

## 邊界 / 刻意不做的事

- **沒有修 `_applyAccountChange` insert 分支的根因**：這個 reconciliation 是「事後偵測+修正」，不是「事前防止寫入錯誤值」——insert 分支仍可能在極端時序下短暫寫入錯誤預設值，但下一次下拉刷新（或任何觸發 `_onRefresh` 的時機）就會自動修正回來，視窗很短。要徹底防堵需要更動 insert 分支本身或接上單一帳戶完整快照拉取，風險/複雜度較高，本次先以自癒機制解決使用者當下的問題。
- **只在手動下拉刷新時觸發**，沒有掛進背景自動 `sync()`（realtime 事件驅動、頻率高）—— 避免每次自動同步都多打一次 `readAccounts()` API。
- **既有已髒的資料需要使用者自行在 App 內手動修正一次估值**（把 `initialBalance` 改回正確值），改完之後這個機制會保護該欄位不再被同類 bug 覆寫回 0——因為修正之後 web/app 兩端的值會一致，比對不會再觸發。

## 後續追蹤：上面的 reconciliation 沒解決使用者的實際問題

使用者套用上述修正後回報「還是沒有」，並提供新截圖：在 App 交易明細裡看到一筆「餘額調整(核對後由 0.00 調整為 ... +2,000)」的交易，掛在同一個估值型帳戶「AIFIAN」底下，但帳戶餘額顯示仍是 0。追查後發現這是**另一個獨立、更根本的 bug**，`reconcileAccountBalances` 幫不上忙：

- 「調整餘額」功能（`lib/utils/account_quick_actions.dart::showBalanceAdjustmentDialog`，比照 BeeCount Cloud 的 `balance_adjustment_ep`）的寫入邏輯是**新增一筆 `type='adjustment'` 交易**去補差額，這對「交易加總型」帳戶（cash/bank 等）有效，但對**估值型帳戶完全無效**——因為 `getAccountBalance()` 對這類帳戶(`isValuationOnlyType`)壓根不看交易紀錄，只讀 `Accounts.initialBalance`。使用者不論在 App 或 BeeCount Cloud 網頁用「調整餘額」，交易本身會正常同步（所以能在 App 交易列表看到它），但帳戶餘額顯示永遠不會變。
  - 帳戶詳情頁本身已經對此有防護（`account_detail_page.dart` 的 `canAdjustBalance = !isValuationOnlyType(...) && account.type != 'account_group'`，估值型帳戶不顯示「調整餘額」按鈕），但**帳戶總覽頁的滑動快捷操作沒有同樣防護**（`accounts_page.dart::_handleSwipeAction`，`AccountSwipeAction.adjustBalance` 分支）——已修正：對估值型/`account_group` 帳戶改為導去帳戶詳情頁並提示改用「更新估值」（新 l10n key `balanceAdjustmentNotSupportedForType`）。
- 估值型帳戶真正該用的是「更新估值」（`account_detail_page.dart::_showUpdateValuationDialog` → `AccountRepository.updateAccountValuation`），直接寫 `initialBalance`。但發現 `LocalRepository.updateAccountValuation`（`local_repository.dart:2643` 附近）**一直是純轉發給 `_accountRepo`，從未呼叫 `changeTracker.recordUserGlobalChange`**——這正是這一系列 bug 的家族模式（`updateAccount`/`setAccountHidden`/`updateAccountSortOrders` 都已在之前的修正中補上同款 change 追蹤，見程式碼裡互相引用的註解，但 `updateAccountValuation` 一直被漏掉，連舊註解都寫著「同 updateAccountValuation 的教訓」卻沒人回頭修它本身）。結果是：**只要用戶在 App 本機用「更新估值」設定過估值，這個值永遠不會被推上雲端**，其他裝置/網頁永遠看不到。

### 這次的修正

- `lib/data/repositories/local/local_repository.dart::updateAccountValuation`：改成跟 `updateAccount` 同款模式——寫完底層後，若帳戶有 `syncId` 就補一條 `recordUserGlobalChange(action:'update')`。
- `lib/pages/account/accounts_page.dart::_handleSwipeAction`：對估值型/`account_group` 帳戶的 `adjustBalance` 滑動操作，改為提示 + 導去帳戶詳情頁，不再打開對這類帳戶無效的「調整餘額」彈窗。
- 新增回歸測試 `test/repositories/account_valuation_sync_test.dart`，比照既有的 `account_sort_order_test.dart` 覆蓋同一類「落值 + 記 change + 無 changeTracker 時不報錯」三個案例。
- 更新了 `account_quick_actions.dart`/`local_repository.dart`/`account_hidden_test.dart` 裡幾處已經過時的註解（原本說「不同步」的地方，現在已經同步了）。

### 使用者要做的事

現有的髒資料（估值一直卡在 0，且從未真正推上雲端過）需要使用者**在 App 的帳戶詳情頁重新走一次「更新估值」**，輸入正確金額（例如 2,000）。這次執行會正確記錄 change 並同步上雲端，之後 App/網頁兩端就會一致。之前那筆「調整餘額」交易本身不必特別處理——它是一筆對餘額顯示無效但本身合法存在的交易，可以留著或刪除都不影響估值。
