# 帳戶「調整總額」(Balance Adjustment)

對齊 BeeCount Cloud 既有的「餘額調整」功能（`tx_type=adjustment`，
`src/routers/write/accounts.py::balance_adjustment_ep`）：使用者輸入調整後應該的
餘額，系統算出差額並建一筆調整交易補上，跟使用者參考的
[doc.moze.app/reconciliation/balance-adjustment](https://doc.moze.app/reconciliation/balance-adjustment)
描述的行為一致。要求是「行為跟 server 一樣，介面可以自己設計」——UI 沒有照抄 Moze 文件
描述的樣子，走 App 現有的設計語言。

這不是既有「對帳模式」(`AccountReconciliationPage`) 的變體——對帳模式只對信用卡（逐筆
核對帳單）有意義；餘額調整對任何非群組帳戶都適用，兩者在 Cloud 端完全不共用程式路徑
（`AccountReconciliationSection.tsx:140-149` 的註解說明了這個分工），這裡也維持分開。

## 發現：地基已經打好，只是沒接 UI

`type: 'adjustment'` 這個交易種類、餘額計算（`local_account_repository.dart` 裡
`getAccountBalance` 已經把 `adjustment` 計入）、l10n 標籤（`adjustmentTransaction`）
都已經存在，但 `TransactionRepository.createAdjustmentTransaction` 在整個
`lib/pages`、`lib/widgets` 裡零呼叫點——是死代碼，這次接上 UI 才第一次真正被用到。

同時發現一個既有 bug：`LocalRepository.createAdjustmentTransaction`
（`local_repository.dart`）直接委托 `_transactionRepo.createAdjustmentTransaction`，
跳過了 `ChangeTracker`——建出來的調整交易不會被記進 `local_changes`，永遠不會同步上
雲端。這次順手修成走 `this.addTransaction(type: 'adjustment', ...)`，跟一般交易走
同一套（含幣種解析 + `changeTracker.recordLedgerChange`）。`test/repositories/
balance_adjustment_test.dart` 有回歸測試鎖住這個路徑。

已確認 App 既有的帳單彙總/回饋計算（`getCreditCardChargedAsOf`、
`getCreditCardPaidTotal`、`getAccountStatementTransactions`、
`card_reward_rule_providers.dart`）全部明確篩選
`type IN ('expense','income')` 或 `type='transfer'`，天生排除 `adjustment`——跟
Cloud 的行為（調整交易不計入帳單週期消費/回饋資格）一致，這部分不需要額外修改。

## 修正：頭部選單改回兩個獨立 IconButton（PopupMenuButton 撞了兩次 framework 斷言）

上線後使用者在 Xcode 跑 macOS 版實測回報兩次不同的整頁紅字錯誤：

1. 點「調整總額」後在對話框裡打字 →
   `'_dependents.isEmpty': is not true'`（`framework.dart:6281` 的
   `InheritedElement.debugDeactivated()` 斷言）。
2. 第一次修完（見下）重新啟動再測 →
   `A GlobalKey was used multiple times`，衝突的 key 是
   `LabeledGlobalKey<NavigatorState>`，父層是 `_FocusInheritedScope`。

第一次的修法是把 `onSelected` 包一層 `WidgetsBinding.instance.addPostFrameCallback` 延後
一個 frame 再開 `showDialog`，想讓 `PopupMenuButton` 自己的退場 Overlay 路由先拆乾淨——
但這只是換了個時間點撞同一類問題，撞出的是 Navigator GlobalKey 重複，證明問題不是「差一個
frame」，而是**把「調整總額」用 `PopupMenuButton` 收進選單、選完馬上疊一個帶
`autofocus: true` TextField 的 `showDialog`（或 push 新頁面）這整個觸發方式本身**跟
Flutter 的 Overlay/Navigator/Focus（`_FocusInheritedScope` 兩次錯誤都點名了它）在桌面版
容易互撞。

真正的修法：**拿掉 `PopupMenuButton`，「調整總額」跟「編輯」改回頭部兩個各自獨立的
`IconButton`**——跟既有「更新估值」按鈕（`ElevatedButton.onPressed` 直接開
`showDialog`，同樣是 `autofocus: true` 的 TextField）一模一樣的觸發方式，這個既有模式
從沒出過問題。改用「選單」收兩個動作是這次功能的 UI 設計選擇，不是需求本身要求的，撞到
兩次 framework 級的 bug 後改用更保守、已驗證安全的模式换掉，不再嘗試用延遲時機去繞過
Overlay/Focus 的競態。

## 改動

- `lib/data/repositories/local/local_repository.dart`：修上述 sync bug。
- `lib/l10n/app_en.arb` / `app_zh_TW.arb`：新增 `balanceAdjustment*` 系列 key（對話框
  文案）與 `txDetailEditDisabledAdjustment`（編輯停用提示）。
- `lib/pages/account/account_detail_page.dart`：
  - 頭部原本單一「編輯」`IconButton` 旁邊多加一個「調整總額」`IconButton`（見上面的
    「修正」小節，最早做成 `PopupMenuButton` 撞了兩次 framework 斷言，改回兩個獨立
    IconButton），只在帳戶不是估值類（`isValuationOnlyType`）且不是帳戶群組
    （`account_group`）時顯示——估值類帳戶已經有自己的「更新估值」流程
    （`_showUpdateValuationDialog` → `updateAccountValuation`，直接改
    `initialBalance`，不建交易、不同步），概念上是同一件事的另一種實作，不重複做；
    帳戶群組沒有自己的餘額。
  - 新增 `_showBalanceAdjustmentDialog`：顯示目前餘額（唯讀）、輸入調整後餘額（預填
    目前值）、可選備註（留空時用 `l10n.balanceAdjustmentDefaultNote(current, target)`
    自動產生，資訊量對齊 Cloud 的預設文案）。確定後算 `diff = target - current`，呼叫
    `repo.createAdjustmentTransaction`，然後 invalidate `accountStatsProvider` +
    `accountTransactionsPaginatedProvider`；若帳戶是信用卡/帳戶群組，額外呼叫既有的
    `_invalidateBillingProviders()`（見 2026-08-18 debt/信用卡系列 change docs 記錄過的
    坑：這族 `FutureProvider.family` 只認 `syncGenerationProvider`，單純本機寫入不會
    自動重算）。
- `lib/widgets/biz/transaction_detail_card.dart`：比照 Cloud「調整交易不可編輯，只能
  刪除重來」，編輯按鈕在 `type=='adjustment'` 時停用（沿用既有 `isTransfer ||
  isAdjustment` 停用退款的寫法擴充），刪除不受影響。

## 刻意不做的部分

- 沒有自訂 `happened_at` 的日期欄位——一律用送出當下的時間，保持對話框簡單（Moze 文件
  描述的介面本身也只有一個金額輸入框）。需要回溯調整日期是超出這次範圍的需求。
- 沒有改 `accounts_page.dart` 帳戶列表的長按選單——目前長按是直接跳編輯，要改成選單是
  更大的既有行為變動，之後有需要再提。
- 對帳金額輸入框沒有做正負號翻轉（不像估值對話框對負債類型做 `-result.abs()`）——這裡
  直接用跟帳戶列表/詳情頁顯示同一個 signed 數字口徑，跟 Cloud `target_balance -
  current_balance` 的算法一致，不需要額外處理。
