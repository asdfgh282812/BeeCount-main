# 信用卡帳單/對帳模組:直接以 Cloud 正式資料庫核對,撤回前一版自創的「繳款期別歸屬」FIFO 模擬

日期:2026-08-18
背景:延續同日稍早的 4 份信用卡繳款/對帳改動文件(`credit-card-payment-moze-parity.md`
→ `credit-card-payment-server-parity-fixes.md` → `credit-card-payment-period-attribution-fix.md`
→ `credit-card-payment-attribution-last-period-fix.md`)。使用者這次直接連線
BeeCount Cloud 正式資料庫(`postgresql://temp_user@10.0.4.20:5431/beecount`,
唯讀查詢)核對「星展信用卡」(`account_group`,子卡「星展eco卡」/「星展
英雄聯盟卡」)三期帳單的真實資料與 Web 端截圖,推翻了前一版的核心結論:
「繳款記錄」清單**不應該**用 FIFO 沖銷模擬去猜一筆繳款「實際歸屬」哪一期
——直接查證 `src/routers/read/ledgers.py::get_account_statement` 並用同一組
SQL 在正式庫上重跑,Cloud 從頭到尾就是單純的日期窗口查詢
(`COALESCE(deferred_posting_at, happened_at)` 落在 `(cycle_start, cycle_end]`
就收,不管這筆錢的「應繳」語意上算哪一期)。前一版的 FIFO 歸屬是 App 端
自己在前端組合出來的假設邏輯,這次連帶查出另外兩個真正的既有 bug。

## 驗證方法

直接用 psql 對正式庫重放 `get_account_statement` 的查詢邏輯(member_ids =
group + 兩張子卡,`attr_date > cycle_start_dt AND <= cycle_end_dt`),核對
星展信用卡三期:

| 帳期 | 新增花費 | 上期欠款 | 應繳 | 已繳 | 剩餘 | 對帳筆數 |
|---|---|---|---|---|---|---|
| 2026/06/11–07/11 | 2,304 | 0 | 2,304 | 2,304 | 0(已繳清) | 6/6 |
| 2026/07/11–08/11 | 4,259 | 0 | 4,259 | 4,259 | 0(已繳清) | 10/10 |
| 2026/08/11–09/11 | 2,812 | 0 | 2,812 | 0 | 2,812 | 0/9 |

第三期的 9 筆明細裡包含 08/12 的兩筆繳款轉入(819、5744)——這兩筆是
`compute_cycle_period_billing` 的終身 watermark 公式(`paid_total` 不設
cutoff)拿去清償了第一、二期的舊欠款(819+5744=6563=2304+4259 剛好整除),
但它們**本身作為交易記錄**,日期就是落在第三期的窗口內,Cloud 的
`get_account_statement` 照樣把它們列在第三期的清單裡——「這筆錢實際拿去
繳了哪期」(watermark 反推的已繳金額)跟「這筆交易記錄顯示在哪一期清單裡」
(日期窗口)是 Cloud 自己就沒有統一、也不打算統一的兩件事。前一版
`period-attribution-fix.md`/`attribution-last-period-fix.md` 想用 FIFO 模擬
把兩者拉齊,方向本身就是錯的。

用同樣的資料重建了 `test/repositories/account_statement_transactions_test.dart`
的端到端 fixture(`getAccountStatementTransactions` 直接用真實金額/日期,
斷言三期的筆數/金額跟上表一致),鎖定這個行為。

> **⚠️ 改動 1 後續被部分恢復**:本文件撤回的「繳款記錄」FIFO 歸屬,使用者
> 隨後用「星展信用卡」實測反饋推翻——「繳款記錄」小節在
> [2026-08-18-credit-card-payment-record-attribution-restore.md](2026-08-18-credit-card-payment-record-attribution-restore.md)
> 恢復了 `attributePaymentsToPeriods`。本文件其餘結論(對帳模式/彙總數字
> 維持 Cloud 純日期窗口/watermark 邏輯)不受影響,仍然成立——見改動 2、3。

## 改動 1(核心):撤回「繳款記錄」FIFO 期別歸屬

- 刪除 `lib/utils/credit_card_payment.dart::attributePaymentsToPeriods`。
- 刪除 `lib/providers/credit_card_billing_providers.dart::creditCardPaymentPeriodRecordsProvider`
  跟它的 helper `_periodNewSpend`。
- 刪除 `AccountRepository.getCreditCardPaymentTransactions`/
  `getCreditCardFirstActivityAt`(介面 + `local_account_repository.dart` 實作 +
  `local_repository.dart` 透傳)——只有上面那個 provider 用,一起刪。
- `account_detail_page.dart::_buildBillingPeriodTransactionList` 的「繳款
  記錄」區塊改回單純用「轉入這張卡/群組」判斷式(`type=='transfer' &&
  toAccountId in ids`)過濾同一份帳期窗口內的交易,跟「一般記錄」同一個
  資料來源、只是分桶不同——不再另外查一個不同口徑的 provider。
- `_buildBillingRecordsSection` 拿掉不再需要的 `isLoading` 參數。
- 刪除對應測試:`test/providers/credit_card_payment_period_records_provider_test.dart`
  整個檔案、`test/utils/credit_card_payment_test.dart` 的
  `attributePaymentsToPeriods` 測試群組(8 例)。

`creditCardDueAsOf`/`getCreditCardChargedAsOf`/`getCreditCardPaidTotal` 這組
真正鏡射 Cloud `compute_cycle_period_billing` watermark 公式的邏輯**沒有
變動**——那不是自創的,是 Cloud 自己就有的終身跑動餘額算法,「應繳/已繳/
剩餘」三個彙總數字繼續用它算,跟上表核對一致。

## 改動 2:帳單彙總卡片的「對帳筆數」誤用了另一個更寬鬆的查詢

`account_detail_page.dart` 原本自己維護一個 `accountBillingPeriodTransactionsProvider`,
底層呼叫通用的 `getAccountTransactions(byEffectiveDate: true)`——這個方法
的 `where` 條件是 `account_id IN (...) OR to_account_id IN (...)`,不分交易
型別。對信用卡帳戶來說,這會把「轉出這張卡的 transfer」也算進「對帳筆數」
的分母/分子,跟 Cloud `get_account_statement`(expense/income 限
`account_id`、transfer 只認「轉入」的 `to_account_id`)的篩選口徑不一致
——也是使用者這次回報「對帳模式混入繳款紀錄、新增消費出現荒謬數字」的
根因之一(另一半根因見改動 3)。

**改法**:直接改用既有的、跟 Cloud 口徑一致的 `accountStatementTransactionsProvider`
(`reconciliation_providers.dart`,`AccountReconciliationPage`/
`AccountReconciliationSection` 本來就在用),`accountBillingPeriodTransactionsProvider`
整個刪除。順帶：

- `getAccountTransactions` 的 `byEffectiveDate` 參數已無任何呼叫端使用,
  一併從介面 + 兩個實作移除(避免留一個死參數)。
- 帳單彙總卡片原本自己另外顯示一行「對帳筆數」,現在跟正下方
  `AccountReconciliationSection`(對帳入口列)的徽章完全同一份資料——
  兩處同時顯示會是純粹的重複 UI(Cloud 網頁版的帳單摘要區塊本來就沒有這一
  行,只有對帳彈窗自己的標題徽章有),這次直接把彙總卡片裡重複的那一行
  刪掉,不再各自查一次。連帶刪除 `billingSummaryReconciledCount` 這個現在
  沒有任何地方引用的 l10n key(`app_en.arb`/`app_zh_TW.arb`,`flutter
  gen-l10n` 重新產生)。
- `AccountReconciliationSection` 的 `onReturn` callback 也跟著拿掉——它原本
  存在的唯一理由就是「額外通知一次帳單彙總卡片的對帳筆數行」,現在兩處
  已經是同一個 family provider 的不同實例,widget 自己那行
  `ref.invalidate(accountStatementTransactionsProvider)`(裸 provider,不帶
  參數)就會讓所有現存實例一起失效重算,不需要呼叫端另外傳一個功能重複的
  callback。

## 改動 3:「新增花費」在當期(尚未結束)帳期沒有 clamp 到現在

Cloud `compute_cycle_period_billing` 算 `new_spend` 時,查詢上界是
`query_end_dt = min(cycle_end_dt, now)`——當期(`cycle_end` 還沒到)如果已經
預先記了未來日期的交易(週期性訂閱、預先排程的分期等),不該提早算進
「新增花費」。`_buildBillingSummaryRows` 原本用 `accountBillingPeriodTransactionsProvider`
拉出的 `txs`(日期窗口本身不 clamp,含未來日期)直接加總,少了這個
clamp——用星展信用卡第三期實測驗證:9 筆明細裡有 2 筆是未來日期(摩托車
969 在 08/25、訂閱 30 在 09/08,相對「今天」08/18 都還沒發生),不 clamp
會把「新增花費」多算成 3,811,而不是 Cloud 顯示的 2,812(差額正好等於
969+30=999,連帶讓反推出來的「已繳金額」出現 999 的異常正數,量級上跟使用者
原始回報的「新增消費: +699」是同一類 bug,只是本次用來核對的資料組合不同)。

**改法**:`_buildBillingSummaryRows` 彙總 `newSpending`/`rewardThisPeriod`
時,額外檢查 `!effectiveDate(tx).isAfter(now)` 才計入——`txs` 本身(供「對帳
筆數」/交易列表用)維持不 clamp,只有這兩個彙總數字加這道過濾。對已經
結束的歷史帳期(前兩期)是無操作(所有交易的入帳歸屬日天然都 <= 現在),
只影響當期。

## 刻意不動的部分

- `docs/changes/2026-08-18-credit-card-payment-period-attribution-fix.md`/
  `-attribution-last-period-fix.md` 兩份文件**沒有刪除**——保留完整歷史,
  讓之後想知道「為什麼一度改成 FIFO 又改回來」的人看得到完整脈絡,只在
  這裡的開頭註明已被推翻。
- `credit_card_group_payment_page.dart`(合併帳單一次繳款、自動分攤到各
  子卡)、`allocateCardPayment`、`findEarliestUnpaidPeriodOffset`(規則一:
  預設停留在最早未清償帳期)都沒有變動——這些都是鏡射 Cloud 既有演算法的
  邏輯(分攤規則/watermark 掃描),不是這次要修正的「自創期別歸屬」問題。

## 測試

- 新增 `test/repositories/account_statement_transactions_test.dart`:直接用
  星展信用卡三期的真實金額/日期重建 fixture,斷言
  `getAccountStatementTransactions` 三期的筆數/金額/是否含轉帳都跟 Cloud
  正式資料庫核對結果一致(見上表)。
- 刪除 `test/providers/credit_card_payment_period_records_provider_test.dart`
  (測的是被刪除的 FIFO provider)。
- `test/utils/credit_card_payment_test.dart` 移除 `attributePaymentsToPeriods`
  測試群組。
- `flutter analyze`:0 error(既有 835 筆噪音跟這次改動無關)。
- `flutter test`:755 個測試全數通過(既有 754 個扣掉刪除的 8 個 FIFO 相關
  案例、加上新增的 1 個端到端案例,以及先前保留的
  `credit_card_charged_deferred_posting_test.dart`/`card_reward_period_test.dart`)。
- 手動驗證(模擬器/實機)待補——這台機器沒有可用的 iOS Simulator/Android
  SDK(同前幾份文件的已知限制),這次改動的信心來源是直接對正式資料庫的
  查詢核對,不是螢幕截圖比對。
