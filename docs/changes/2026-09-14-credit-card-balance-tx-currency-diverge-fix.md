# 信用卡帳戶餘額/帳單計算未跟上「交易幣別可跟帳戶脫鉤」

## 問題

使用者反饋:台幣信用卡(uniopen聯名卡)記一筆日圓 600 元的消費(記帳當下換算預覽正確顯示「≈123.65 TWD」),但：

- 帳戶明細頁的「剩餘帳款」顯示 `-600`,不是折算後的 `-123.65`。
- 「一般記錄」清單裡這筆交易也顯示 `-600`,沒有任何幣別/折算標示。
- 首頁交易清單顯示金額數字是對的,但幣別標示用的是貨幣符號(`¥-600 ≈123.65`)——使用者後續回報這個符號在 JPY/CNY 之間有歧義,見下方「追加」段落。

## 根因

[2026-09-13-tx-currency-account-decouple.md](2026-09-13-tx-currency-account-decouple.md) 讓交易的 `currencyCode` 可以不再等於所屬帳戶的 `currency`(例如台幣帳戶記一筆日圓交易,對齊 Cloud 網頁端行為)。但信用卡帳戶餘額/帳單相關的計算邏輯沒有跟著這個變動更新,仍然假設「單一帳戶(非合併帳單群組)的交易一定跟帳戶同幣別」,直接把 `amount`(交易自己幣別下的原始數字)當成帳戶自身幣別下的金額加減:

- [`lib/data/repositories/local/local_account_repository.dart`](../../lib/data/repositories/local/local_account_repository.dart) 的 `getAccountBalance`(一般帳戶餘額)完全沒有做任何幣別判斷。
- 同檔案 `getCreditCardChargedAsOf` 只在 `convertToLedgerCurrency: true`(合併帳單群組場景)才折算,單一帳戶固定用原始 `amount`。
- [`lib/pages/account/account_detail_page.dart`](../../lib/pages/account/account_detail_page.dart) 的 `_buildBillingSummaryRows`(帳單彙總卡片「新增花費」/「應繳金額」)、`TransactionTile`(「一般記錄」清單金額)同樣只判斷「是不是合併帳單群組」,單一帳戶一律讀原始 `amount`。

這些函式原本的假設在 `currencyCode` 恆等於帳戶自身幣種時是成立的,一旦交易幣別可以脫鉤就會把外幣原始數字當成帳戶自身幣別的金額直接計入。

`getCreditCardPaidTotal`(已繳金額,對應轉帳交易)不受影響——轉帳走的是 `amount`/`toAmount` 這組欄位(轉入方在轉入帳戶自身幣別下的金額,由轉帳表單在記帳當下换算好),跟 `currencyCode`/`nativeAmount` 是兩套機制,沒有本次的問題。

## 修正

改用「這筆交易自己的 `currencyCode` 是否跟(顯示時要對齊的)目標幣別不同」來決定要不要折算,而不是「是不是合併帳單群組」:

- 同幣別(絕大多數交易,含所有既有資料):維持讀原始 `amount`,行為完全不變。
- 不同幣別:改讀 `nativeAmount ?? amount`(記帳當下折算到帳本本位幣的快照)。

折算目標嚴格來說該是「這筆交易所屬帳戶自身的幣別」,但 `nativeAmount` 記錄的是折算到**帳本本位幣**的快照,兩者只有在帳戶自身幣別＝帳本本位幣時才完全相等(信用卡帳戶絕大多數情況下就是這樣,包含這次回報的案例)。帳戶自身幣別本身也是外幣、且交易幣別跟該帳戶幣別是「第三種」幣別的情況(理論上可能,透過帳戶編輯頁可以把信用卡幣別設成任意值),目前沒有「即時折算成任意帳戶幣別」的查詢,`nativeAmount` 只能當近似值——這跟合併帳單群組既有的折算方式(`convertToLedgerCurrency: true` 一律讀 `nativeAmount ?? amount`,不管子卡自身幣別是什麼)是同一個既有近似,不是本次修正新增的限制,超出範圍不處理。

具體改動:

- `local_account_repository.dart` 新增私有 helper `_amountInAccountCurrency(tx, accountCurrency)`,`getAccountBalance` 的 income/expense/adjustment 三個分支改呼叫它;`getCreditCardChargedAsOf` 額外查一次帳戶自身幣別、SQL 多選 `currency_code` 欄位,單一帳戶場景比照同一條件折算(合併帳單群組 `convertToLedgerCurrency: true` 的既有行為不變)。
- `account_detail_page.dart`:`_buildBillingSummaryRows` 的 `isGroup` 判斷式擴充為 `isGroup || 這筆交易 currencyCode 跟 account.currency 不同`。

### 追加(同日,使用者第二次反饋):「一般記錄」清單改成雙幣別顯示

金額數字修正之後,使用者接著反饋:外幣交易應該比照首頁交易清單先顯示外幣原始金額、再顯示「≈折算金額」小字,而不是只顯示折算後的單一數字(否則看不出這筆錢實際上是用多少日圓扣款的)；同時幣別**不要用貨幣符號**(¥ 同時是 JPY/CNY 的符號,容易混淆),改用幣別縮寫文字(例如 `JPY`)。

`TransactionTile`(`account_detail_page.dart`)的 expense/income 金額欄位改為:交易自己的 `currencyCode` 跟顯示用的帳戶幣別不同時,分兩行呈現——

- 第一行:`{幣別縮寫} {原始外幣金額}`(例如 `JPY -600`),`AmountText` 一律 `showCurrency: false`,幣別縮寫另外用一個 `Text` 手動畫,不走 `getCurrencySymbol` 這條會出符號的路徑。
- 第二行:`≈{nativeAmount 折算後金額}`,格式對齊首頁 `TransactionListItem` 既有的「≈」小字(`toStringAsFixed(2)`,不帶正負號)。

同幣別(絕大多數交易)維持原本單行顯示,不受影響。轉帳不套用這個顯示(轉帳沒有 `currencyCode`/`nativeAmount` 這組欄位,幣別轉換走的是 `toAmount`,見上)。

### 追加(同日,使用者第三次反饋):首頁交易清單也要換成幣別縮寫文字

使用者接著回報首頁交易清單(`lib/widgets/biz/transaction_list_item.dart`,`TransactionListItem`,被 `calendar_body.dart` 等處用來畫每日交易列表)還是顯示 `¥-600`——這是另一個獨立元件,前一輪只改了帳戶明細頁的 `TransactionTile`,沒有覆蓋到這裡。

`TransactionListItem` 原本的 v30 多幣種顯示是 `AmountText(showCurrency: _isForeign(ref), currencyCode: currencyCode, ...)`,`showCurrency: true` 會讓 `AmountText` 內部呼叫 `getCurrencySymbol` 在金額前加貨幣符號(`¥`/`$`/`€`…)。改成:`showCurrency` 一律 `false`,外幣時改在 `AmountText` 前面另外插一個 `Text(currencyCode!.toUpperCase())` 顯示幣別縮寫(例如 `JPY`),不透過 `getCurrencySymbol`。下方既有的「≈折算金額」小字不受影響(那行本來就是純數字,不是本次问题來源)。

### 追加(同日,使用者第四次反饋):搜尋頁 + 交易詳情卡也要換成幣別縮寫文字 + 折算金額

- 搜尋頁(`lib/pages/transaction/search_page.dart`)其實**不需要改**——每一筆搜尋結果本來就是重用 `TransactionListItem` 畫的(`search_page.dart:1196`),上一輪的 `TransactionListItem` 修正已經自動涵蓋這裡。搜尋頁自己另一個 `showCurrency: true` 的地方(`_buildSummaryChip`,line 700 附近)是收支彙總小標籤,顯示的是帳本本位幣(單一、明確的幣別,沒有「哪個幣別」的歧義),跟本次「外幣交易標示不清」的問題無關,沒有動它。
- 交易詳情卡(`lib/widgets/biz/transaction_detail_card.dart`,`showTransactionDetailCard` 打開的那張卡)有 4 處用 `AmountText(showCurrency: ...)` 顯示幣別符號,原本各自的判斷條件不一致(`tx.currencyCode != null`——因為每筆交易的 `currencyCode` 幾乎都會被 `_resolveTxCurrency` 補上預設值,這個條件其實恆真;或甚至無條件 `true`)。這次統一改用新增的頂層 helper `_txIsForeign(tx)`(`tx.nativeAmount != null && tx.nativeAmount != tx.amount`——同幣別時 `nativeAmount` 恆等於 `amount`,不需要另外查帳本本位幣比較,見 `_resolveTxCurrency` 注解)當作唯一判斷依據,順便修正了「同幣別交易也會顯示幣別符號」這個既有的小瑕疵。
  - **頭部主金額**(`_buildNoteAmountRow`):外幣時分兩行,比照 `TransactionTile`/`TransactionListItem` 顯示 `{幣別縮寫} {原始金額}` + `≈{折算金額}`。
  - **拆帳明細列**(`_buildSplitSection`):拆帳明細沒有自己的 `currencyCode`/`nativeAmount`(跟母交易同幣別,`TransactionSplits` schema 本來就沒有這兩個欄位),改按這筆分帳金額佔母交易總額的比例,從母交易的 `nativeAmount` 按比例折算(`splitNative = s.row.amount / tx.amount * tx.nativeAmount`),同樣分兩行顯示。
  - **手續費/折扣小字提示**(`buildFeeDiscountSubtitle`,同時被 `account_reconciliation_page.dart` 的對帳清單列重用,函式簽名沒變,呼叫端不用改):只把符號換成幣別縮寫文字,沒有逐項加「≈」——這行本身是「(原始金額 X + 手續費 Y)」這種密集的行內組字,原始金額/手續費/折扣都是同一筆總額的組成部分,逐項再加一行折算金額會讓版面過度擁擠,判斷可讀性後決定省略。
  - **信用卡回饋估算行**(`_RewardRuleRow`):原本無條件 `showCurrency: true`,改成同樣用 `_txIsForeign(tx)` 判斷,只換符號成文字,同樣不加「≈」——這是一個回饋金額的估算值,不是交易本身的金額,加上按比例折算的「≈」意義不大。

## 沒有改變的行為

- `getCreditCardPaidTotal`/轉帳相關計算不受影響,原因見上。
- 帳單彙總卡片(「新增花費」/「應繳金額」/「剩餘帳款」)維持顯示單一折算後的數字,沒有比照「一般記錄」清單做雙幣別呈現——那幾個是加總後的彙總數字,加總前逐筆列出原始外幣金額沒有意義。
- 搜尋頁的收支彙總小標籤維持顯示貨幣符號,原因見上。
- 交易詳情卡的手續費/折扣小字提示、信用卡回饋估算行只換符號成文字,沒有加「≈折算金額」,原因見上。

## 測試

- [`test/repositories/credit_card_tx_currency_diverge_test.dart`](../../test/repositories/credit_card_tx_currency_diverge_test.dart):重現「台幣信用卡記一筆日圓 600 元消費」場景,驗證 `getCreditCardChargedAsOf`/`getAccountBalance` 都得到折算後的 123.65,並補一個同幣別對照組確認既有行為不受影響。
- [`test/widgets/account_detail_transaction_tile_foreign_currency_test.dart`](../../test/widgets/account_detail_transaction_tile_foreign_currency_test.dart):驗證 `TransactionTile` 在幣別不同時顯示幣別縮寫文字(`JPY`)+ 原始外幣金額(`600`)+ 折算後金額(`≈123.65`),且不出現貨幣符號(`¥`);同幣別對照組驗證維持單行顯示、不出現多餘文字。
- [`test/widgets/transaction_list_item_foreign_currency_test.dart`](../../test/widgets/transaction_list_item_foreign_currency_test.dart):同樣的斷言套用在 `TransactionListItem` 上。
- [`test/widgets/transaction_detail_card_foreign_currency_test.dart`](../../test/widgets/transaction_detail_card_foreign_currency_test.dart):驗證交易詳情卡頭部金額的幣別縮寫文字 + `≈` 折算金額;同幣別對照組確認不受影響;拆帳場景驗證兩筆分帳明細各自按比例折算出正確的「≈」金額(600/1000×200=120.00、400/1000×200=80.00)。

既有信用卡帳單相關測試(`test/repositories/`、`test/providers/`、`test/widgets/` 全部)+ 上述 4 個新測試,全數通過(`test/widgets/calendar_month_jump_test.dart` 有一個既有失敗案例,跟本次改動無關——在改動前的程式碼上跑同一個測試就已經失敗)。
