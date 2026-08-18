# 信用卡帳單:charged_as_of 未使用入帳歸屬日,導致延後入帳交易算錯期

日期:2026-08-18
背景:延續 [2026-08-18-credit-card-payment-server-parity-fixes.md](2026-08-18-credit-card-payment-server-parity-fixes.md)
的 4 個 bugfix,使用者用同一張「遠東快樂卡」再測了一輪,帶了新的截圖與更
細的線索:一筆 2026-08-05、140 元、狀態「已延後」(對帳模式裡標記延後入帳)
的交易,讓「交易明細」tab 顯示「新增花費 -7,477、上期欠款 +0、已繳金額
+0」,但「剩餘帳款」卻是 -7,617(多了 140),倒推出「已繳金額 -140」這種
不合理的負數。另外附了一張「星展信用卡」的截圖,質疑 08/12 繳的款(結清
07/11–08/11 那期)在切到 08/11–09/11 期別瀏覽時,是否有「繳款期別歸屬」
算錯的問題。

## 根因:`getCreditCardChargedAsOf` 用原始交易日截斷,沒有用入帳歸屬日

`account_repository.dart::getCreditCardChargedAsOf` 上一輪新增時用的截斷條件
是 `happenedAt <= asOf`。但同一個帳期的「新增花費」(`_buildBillingSummaryRows`
呼叫 `accountBillingPeriodTransactionsProvider`,底層
`getAccountTransactions(byEffectiveDate: true, ...)`)跟「一般記錄/繳款記錄」
清單,用的都是 `COALESCE(deferredPostingAt, happenedAt)` 這個「入帳歸屬日」
做帳期過濾(`local_account_repository.dart` 既有的
`getAccountStatementTransactions`/`getAccountTransactions` 都是這個口徑,對齊
BeeCount Cloud `attribution_date_expr()`/`_ATTR_DATE`)。這筆 140 元交易的
`happenedAt` 是 8/5(落在舊帳期內),但 `deferredPostingAt` 已經被改到下一期
——「新增花費」用歸屬日過濾,正確地把它排除在外(顯示 7,477);但
`getCreditCardChargedAsOf` 還在用 `happenedAt`,依然把它算進舊帳期的
`charged`(變成 7,617)。`remainingDue = max(charged − paidTotal, 0)` 因此比
`totalDue`(= priorDue + 新增花費)多了整整 140,而「已繳金額」是反推出來
的(`totalDue − remainingDue`),於是變成 -140。

**改了什麼**:`local_account_repository.dart::getCreditCardChargedAsOf` 改成
`customSelect` 原生 SQL,篩選條件從 `happened_at <= ?` 換成
`COALESCE(deferred_posting_at, happened_at) <= ?`,寫法比照同檔案裡已有的
`getAccountStatementTransactions`(用 `_kExcludeJoinedSharedLedgerSql` 常數
取代原本額外查一次 `_sharedLedgerIds()` 的做法,少一次查詢往返,語意不變)。
`account_repository.dart` 介面上的文件註解同步更新,明確寫出「用入帳歸屬日
而非原始交易日」這個約束,避免以後又被改回 `happenedAt`。

`getCreditCardPaidTotal`(已繳總額,FIFO watermark 用的終身加總)**沒有改**
——比對 Cloud `compute_cycle_period_billing` 原始碼(`paid_total` 那段查詢),
`paid_total` 完全沒有任何日期篩選條件,不是「用歸屬日代替交易日」,是徹底
不設時間上界,這點 App 端本來就已經對齊,不需要動。

`getCreditCardChargedAsOf`/`getCreditCardPaidTotal` 是
`credit_card_billing_providers.dart` 裡 `defaultBillingPeriodOffsetProvider`
(規則一:預設帳期)、`accountBalanceAsOfProvider`(彙總卡片的上期欠款/
剩餘帳款)、`creditCardBillingBadgeProvider`(帳戶列表徽章)三處共用的唯一
資料來源,這次只改了 repository 這一處,三個 provider 跟
`credit_card_group_payment_page.dart` 的群組分攤金額全部自動一起修正,不需要
逐一改呼叫端。

## 「星展信用卡」的繳款期別歸屬:讀原始碼確認不是 bug

比對 BeeCount Cloud `routers/read/ledgers.py::get_account_statement`(對帳
模式清單的端點,跟「繳款記錄」清單同一套歸屬日篩選邏輯)原始碼後確認:
**Cloud 本身的繳款記錄清單就是按繳款交易自己的入帳歸屬日落在哪一期過濾**
(`attr_date > cycle_start_dt AND <= cycle_end_dt`,轉帳交易同樣適用這個
`COALESCE(deferredPostingAt, happenedAt)` 條件),不是按「這筆錢實際沖銷了
哪一期的帳」歸屬。這跟「剩餘帳款」/「已繳金額」的計算是刻意分開的兩件事:
後者靠 `paid_total` 終身不設 cutoff、`charged_as_of` 按 FIFO 逐期沖銷的
watermark 公式(見上方 `docs/changes/2026-08-18-credit-card-payment-server-parity-fixes.md`
第 1 節),不管繳款發生在哪一期,都會優先沖銷最舊的未清償帳期——「星展
信用卡」截圖裡 08/12 的繳款雖然被列在 08/11–09/11 期的「繳款記錄」裡(因為
繳款這個動作本身發生在那個窗口內),但 08/11–09/11 期彙總卡片顯示的
「已繳金額 +999」「剩餘帳款 -2,812」已經是套用 FIFO watermark 沖銷過舊帳期
後的正確結果(手算驗證:`charged_as_of(cycle_end) − paidTotal` 恆等於
`剩餘帳款`,`total_due − remaining_due` 恆等於 `已繳金額`,兩條算式跟畫面
數字對得上,且 `已繳金額` 是正數,不是使用者擔心的「跨期金額混雜出負數」
情況)。**這次沒有另外改繳款清單/沖銷邏輯**——結論記錄在這裡,供之後若
使用者再回報「繳款記錄清單顯示的期別跟我以為的不一樣」時,第一個該複查
的是這裡的說明,而不是重新假設有 bug。

## 測試

新增 `test/repositories/credit_card_charged_deferred_posting_test.dart`(用
`BeeDatabase.forTesting(NativeDatabase.memory())` + `LocalRepository`,不是
純函式單元測試,因為這個 bug 本身就是 SQL 篩選條件的問題,純函式測試測不
出來):
- 一筆交易 `happenedAt` 在舊帳期、`deferredPostingAt` 延後到下一期:截斷在
  舊帳期結束日時不應計入,截斷在新帳期結束日時才計入。
- 沒有延後入帳的交易,行為不變(對照組,防止之後又改壞)。

## Verification

- `flutter analyze` 涉及的 3 個檔案:0 issue。
- `flutter test`:754 個測試全數通過(既有 752 + 這次新增 2 個)。
- 手動驗證(模擬器/實機)待補。
