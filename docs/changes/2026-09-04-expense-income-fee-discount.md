# 支出/收入手續費/折扣

App 端支出/收入交易一直沒有「手續費/折扣」欄位,但 BeeCount Cloud 早在
`0039_tx_fee_discount.py`(2026-08)就已經為 expense/income 提供了這組欄位
(比照 Moze),App v46 只把其中 `feeAmount`/`feeLabel`/`discountAmount`/
`discountLabel` 四個欄位搬過來、卻只放行給 transfer 使用。這次把支出/收入
的手續費/折扣邏輯跟 UI 補齊,直接沿用 Cloud 既有公式與 wire 欄位。

## 資料層

- `lib/data/db.dart`:`Transactions` 新增 `baseAmount`(nullable REAL),
  schemaVersion 50 → 51。這是唯一真正的新欄位——`feeAmount`/`feeLabel`/
  `discountAmount`/`discountLabel` 早就存在(v46),只是先前只服務
  transfer。`baseAmount` 對齊 Cloud `read_tx_projection.base_amount`:使用者
  輸入的原始金額,`amount` 才是套用公式後、實際入帳驅動餘額/統計的淨額。
- `lib/utils/amount_calculator.dart`:新增 `computeFeeDiscountNetAmount`,
  對齐 Cloud `_compute_fee_discount_amount`(`routers/write/_shared.py`):
  - `expense: amount = baseAmount + feeAmount − discountAmount`
  - `income:  amount = baseAmount − feeAmount + discountAmount`
  - 用 `Decimal` 算(跟既有 `computeAmountOp` 同款寫法,避免浮點漂移),
    結果四捨五入到兩位小數,不額外擋淨額變負數——比照 Cloud 本身也沒擋。
  - 只接受 `expense`/`income`;transfer 的手續費/折損邏輯不同(疊加在
    餘額計算上的獨立 delta,不動 `amount` 本體),不套這條公式。

## 寫入路徑(哪裡做這個計算)

Cloud 在 server 端統一重算 `amount`,但 App 的本地 repository
(`LocalTransactionRepository.addTransaction`/`updateTransaction`)向來是
「呼叫端算好、repo 只負責存」的慣例(轉帳的 `feeAmount`/`discountAmount`
就是這樣),沒有「先查現有列再合併」的 partial-update 機制。維持這個既有
慣例,`computeFeeDiscountNetAmount` 的呼叫點在
`transaction_entry_form.dart` 的 `_submit()`(表單送出前),不是
repository 層——`baseAmount`/`feeAmount`/`discountAmount` 三者一起算出
`amount` 後才傳給 repo,repo 只是多存一個 `baseAmount` 欄位,行為跟既有的
`feeAmount`/`discountAmount` 完全對稱。

`TransactionRepository`(介面)/`LocalRepository`(聚合層)/
`LocalTransactionRepository`(實作)三層都加了 `baseAmount` 參數
(`addTransaction` 用 `double?`,`updateTransaction` 沿用既有
`feeAmount` 那組的 `dynamic` tri-state 寫法)。

## Sync 推拉

- `lib/cloud/sync/entity_serializer.dart`:push 時「有值才發」帶上
  `baseAmount`(camelCase),對齐 Cloud `sync_applier.py`
  `_LEDGER_MERGE_SPECS["transaction"]` 既有的 `("baseAmount",
  "base_amount")` merge spec——這個 spec 原本就在,只是 App 之前沒有本地
  欄位可以填。
- `lib/cloud/sync/sync_engine_apply.dart`:pull 時比照 `feeAmount` 那組的
  「缺鍵不覆蓋」寫法解析 `baseAmount`。
- 週期性交易規則(`RecurringTransactions`)刻意不動——範圍決策沿用既有的
  「App 端週期規則不支援 fee/discount」排除項(`entity_serializer.dart`/
  `sync_engine_apply.dart` 裡舊有的說明)。

## UI

- 抽出共用元件 `lib/widgets/biz/amount_adjustment_panel.dart`
  (`AdjustmentToggleButton` + `AdjustmentFieldRow`),把原本只有
  `transfer_form.dart` 在用的「金額旁『+』展開名稱/金額欄」那套 UI 程式碼
  抽成兩邊共用,`transfer_form.dart` 同步改成呼叫共用元件(純重構,外觀/
  行為不變,含既有的 `transferFeeToggle`/`transferFeeLabelField` 等 Key
  不變,不影響既有測試)。
- `transaction_entry_form.dart`(支出/收入表單)在金額列旁加一個單一
  「+」按鈕(`Key('feeDiscountToggle')`),跟轉帳「轉出/轉入各自一個開關」
  不同——支出/收入只有一個方向,點下去展開單一面板,裡面同時放手續費列
  (`feeLabelField`/`feeAmountField`)、折扣列
  (`discountLabelField`/`discountAmountField`)、以及即時計算的淨額預覽
  (`總額 xxx`),對齐 BeeCount Cloud 網頁版 `TransactionsPanel.tsx` 的單一
  面板設計,也是這次使用者要求比照的 Moze 風格。拆帳模式下不提供(比照
  「進階設定」跟拆帳互斥的既有規則)。
- 主金額輸入(小算盤)語意變成「使用者輸入的原始金額」(`baseAmount`);
  編輯既有交易時,若有 `baseAmount` 就回填面板並讓小算盤顯示原始金額,而
  不是套用公式後的淨額(比照轉帳 `initialFeeAmount` 等既有回填寫法)。
- 金額輸入框本身(`AmountCalculatorKeypad`)刻意不改動樣式——跟使用者
  討論過,風險/收益比不划算,只在旁邊加 Moze 風格的「+」即可。
- `transaction_editor_page.dart`:`TransactionEditorPage` 既有的
  `initialFeeAmount`/`initialFeeLabel`/`initialDiscountAmount`/
  `initialDiscountLabel`(原本只傳給 `TransferForm`)現在也一併傳給兩個
  `TransactionEntryForm`(支出/收入),新增 `initialBaseAmount` 走一樣的
  管道;`_handleSubmit` 把 `AmountEditorResult` 的這五個欄位透傳給
  `addTransaction`/`updateTransaction`。三個既有呼叫端
  (`transaction_edit_utils.dart` 的編輯/複製、`ai_chat_page.dart` 的編輯)
  都補上 `initialBaseAmount: transaction.baseAmount`。

## 明確排除範圍

- 週期性交易規則、分期付款(另一個獨立功能)、應收/應付款項(debt,另一個
  表單)、拆帳模式——都不支援手續費/折扣,維持現狀。
- 沒有額外擋「折扣 > 本金 + 手續費」導致淨額變負數的情況,原樣比照 Cloud
  的行為(只驗證三個分量各自 ≥ 0)。

## 測試

- `test/data/migration_v51_test.dart`:schema 遷移,新欄位存在、舊資料
  讀回為 null。
- `test/utils/amount_calculator_fee_discount_test.dart`:
  `computeFeeDiscountNetAmount` 純函式的公式/浮點精度/負值邊界案例。
- `test/widgets/transaction_entry_form_fee_discount_test.dart`:面板展開、
  送出後 `AmountEditorResult` 的五個欄位跟重算後的 `amount` 正確、負數擋
  下送出、編輯模式回填。
- `test/widgets/transfer_form_fee_discount_test.dart`(既有):驗證抽共用
  元件後轉帳的行為/Key 不變,全數通過。
