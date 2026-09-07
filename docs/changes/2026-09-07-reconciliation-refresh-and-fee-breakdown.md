# 對帳模式:編輯後不刷新的修正 + 手續費小字提示補上原始金額

使用者反饋(錄影重現):在對帳模式頁面點編輯鉛筆修改一筆交易的金額後,回到
清單金額還是舊值,過了一小段時間(或再操作一次)才變成新值,導致誤以為
「編輯沒有生效」而重複編輯同一筆。另外手續費小字提示只顯示「(內含 手續費
NT$36)」,只看得到手續費本身,對帳時看不到原始金額,得自己心算。

## 1. 對帳模式編輯後不刷新

根因分兩層:

- [lib/widgets/biz/transaction_detail_card.dart](../../lib/widgets/biz/transaction_detail_card.dart)
  的 `_handleEdit`:點交易詳情卡片內的鉛筆時,會先 `Navigator.of(context).pop()`
  把詳情卡片本身關掉,**再** `push` 完整的 `TransactionEditorPage`(用呼叫端的
  `hostContext`,因為卡片自己的 `context` 這時已經 dispose)。這代表
  [lib/pages/account/account_reconciliation_page.dart](../../lib/pages/account/account_reconciliation_page.dart)
  的 `onEdit`(`await showTransactionDetailCard(...)` 之後才呼叫 `_invalidate()`)
  裡,`showTransactionDetailCard` 回傳的 Future 在使用者「打開完整編輯器的那一
  刻」就已經 resolve——遠早於使用者真正按下儲存。`_invalidate()` 因此在編輯發生
  *之前* 就白跑一次,儲存*之後*沒有任何程式碼再通知對帳頁。
- [lib/providers/reconciliation_providers.dart](../../lib/providers/reconciliation_providers.dart)
  的 `accountStatementTransactionsProvider`(`FutureProvider.family.autoDispose`)
  原本只 `ref.watch(syncGenerationProvider)`——這顆計數器只在**遠端 pull 套用**
  時才 bump(自己這台裝置寫入、`PostProcessor.sync` 背景推播上去的變更,通常會
  被「自我推送回聲」過濦掉,不會讓這顆計數器 bump),對本機自己的編輯完全沒有
  反應。

**沒有修 `_handleEdit` 的 pop 順序**(那是刻意設計,detail card 的 context 在
push 全螢幕編輯器前本來就要讓路,牽動範圍較大),改成讓
`accountStatementTransactionsProvider` 額外
`ref.watch(statsRefreshProvider)`——這是專案裡「任一交易寫入後刷新」的既有全域
tick(`TransactionEditorPage._handleSubmit`/刪除/AI 對話/語音/照片/背景自動記帳/
CSV 匯入/週期性交易產生器等寫入路徑統一都會 bump),`account_period_providers.dart`
的帳戶明細頁摘要/趨勢 provider 已經是同樣寫法,對齊既有慣例。不論呼叫端的
`Navigator` pop/push 時機多脆弱、`onEdit` 的 `_invalidate()` 有沒有在正確時機
呼叫,存檔後這顆 tick 一定會 bump,對帳頁的 `FutureProvider` 就能可靠重算。

**已知殘留缺口(非本次修改引入,`account_period_providers.dart` 等既有共用
`statsRefreshProvider` 的頁面同樣受影響,不在本次範圍內修)**:
- [lib/utils/transaction_edit_utils.dart](../../lib/utils/transaction_edit_utils.dart)
  的 `_deleteOrphanInstallmentTransaction`(孤兒分期交易刪除)只 bump
  `installmentsRefreshProvider`,不 bump `statsRefreshProvider`。
- [lib/pages/transaction/search_page.dart](../../lib/pages/transaction/search_page.dart)
  的三個批次操作(`_executeBatchDelete`/`_executeBatchSetNote`/
  `_executeBatchChangeCategory`)完全不 bump `statsRefreshProvider`,只 bump
  `budgetRefreshProvider`/`debtsRefreshProvider`,靠自己重新查詢列表。

若使用者從搜尋頁批次刪除/改分類某張信用卡的交易,或刪除孤兒分期交易,對帳模式
仍不會即時刷新——這兩處要堵住需要各自補 `ref.read(statsRefreshProvider.notifier)
.state++`,超出這次「編輯單筆交易」的問題範圍,故未動。

## 2. 手續費/折扣小字提示補上原始金額

[lib/widgets/biz/transaction_detail_card.dart](../../lib/widgets/biz/transaction_detail_card.dart)
的 `buildFeeDiscountSubtitle`(交易明細卡跟對帳模式清單共用):格式從
「(內含 手續費 NT$36)」改成「(原始金額 NT$2,407 + 手續費 NT$36)」——把 v51
`Transaction.baseAmount`(使用者輸入的原始金額)也帶出來,讓「原始金額 + 手續費
− 折扣 = 淨額」這條算式可以直接核對,不用自己心算(單看淨額看不出來裡面含了
多少手續費/折扣)。折扣同時存在時接在後面:「(原始金額 NT$2,407 + 手續費
NT$36 − 折扣 NT$10)」。

- 移除不再需要的 `txDetailFeeDiscountPrefix`(「內含」)/
  `txDetailFeeDiscountSeparator`(「、」)兩個 l10n key(改用 `+`/`−` 符號直接
  拼接,不需要另外翻譯),新增 `txDetailOriginalAmountLabel`(「原始金額」/
  `Original amount`)。`app_en.arb` + `app_zh_TW.arb`(本專案目前只維護這兩個)
  跑過 `flutter gen-l10n`。
- `baseAmount` 為 `null` 時(理論上不會發生在這個函式被呼叫到的分支,因為
  feeAmount/discountAmount 非零時 v51 寫入路徑一定會同時寫入 baseAmount)不顯示
  原始金額那一段,只保留手續費/折扣,不強制假設一定拿得到。

## 測試

- [test/widgets/transaction_detail_card_fee_discount_test.dart](../../test/widgets/transaction_detail_card_fee_discount_test.dart):
  更新既有斷言,「支出帶手續費」案例改成核對「原始金額」「2,651」「手續費」
  「40」都出現;「未啟用」「轉帳」兩個「不顯示」案例的斷言從 `內含` 改成
  `原始金額`(檢查點對齐新格式的標記文字)。
- `accountStatementTransactionsProvider` 的刷新修正沒有新增自動化測試——它是
  Riverpod provider 的 watch 相依關係調整,現有
  `test/repositories/account_statement_transactions_test.dart` 只測底層 SQL 查詢
  邏輯(不經過 Riverpod),要驗證「編輯後自動重算」需要 widget 測試模擬完整
  `showTransactionDetailCard → TransactionEditorPage → 儲存` 導航鏈,超出這次
  修改的成本考量,已用 `flutter analyze` + 手動核對程式碼路徑確認。
