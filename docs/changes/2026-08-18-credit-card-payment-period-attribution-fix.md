# 信用卡「繳款記錄」依沖銷帳期歸屬,不再按交易發生日切分

> **⚠️ 一度被推翻,後來又恢復(範圍收窄)**:這份文件跟下一份
> `-attribution-last-period-fix.md` 提出的 FIFO 期別歸屬,曾在
> [2026-08-18-credit-card-reconciliation-cloud-parity-fix.md](2026-08-18-credit-card-reconciliation-cloud-parity-fix.md)
> 被撤回(理由:Cloud `get_account_statement` 沒有這種歸屬概念)。但使用者
> 隨後用「星展信用卡」實測反饋明確要求「繳款記錄」小節要用這套歸屬邏輯
> 顯示,在
> [2026-08-18-credit-card-payment-record-attribution-restore.md](2026-08-18-credit-card-payment-record-attribution-restore.md)
> 恢復了 `attributePaymentsToPeriods`(用下一份文件定案的 `lastTarget` 規則,
> 不是這份文件最初的 `firstTarget`),但**只套用在「繳款記錄」小節**,對帳
> 模式/彙總數字繼續維持 parity-fix 文件的純日期窗口/watermark 邏輯不變。

日期:2026-08-18
背景:延續 [2026-08-18-credit-card-payment-server-parity-fixes.md](2026-08-18-credit-card-payment-server-parity-fixes.md)
第 2 節、[2026-08-18-credit-card-charged-deferred-posting-fix.md](2026-08-18-credit-card-charged-deferred-posting-fix.md)
的結論——當時查證 BeeCount Cloud 的「繳款記錄清單」本來就是按繳款交易自己
的日期落在哪個帳期過濾,兩篇文件都認定 App 端這個行為「不是 bug,是刻意
跟 Server 對齊的口徑」。這次使用者用「星展信用卡」實際場景推翻了這個結論
(附截圖):08/12 的繳款是為了結清 `2026/07/11–2026/08/11` 那期帳單(繳款
截止日 08/27),但因為 08/12 落在下一期(`08/11–09/11`)的日期窗口內,舊版
「繳款記錄」清單只在下一期顯示這筆交易,`07/11–08/11` 這期的「繳款記錄」
區塊顯示「無交易記錄 (0)」,卻跟同一頁摘要卡片的「已繳金額 +4,259」互相
矛盾——使用者要的是**清單跟摘要數字一致**,不是跟 Server 的歷史行為一致。
這次明確改成 App 自己的行為,不再跟 Cloud 的清單口徑對齊。

## 核心改動:「繳款記錄」清單改用 FIFO 沖銷模擬,不用日期窗口過濾

`_buildBillingSummaryRows` 的「已繳金額」欄位本來就已經是從 watermark
反推出來的正確值(`totalDue − remainingDue`,鏡射 Cloud
`paid_in_cycle = total_due - remaining_due`),不管繳款實際發生在哪一期都會
正確反映。這次要讓「繳款記錄」清單也採用同一套邏輯,而不是只挑「交易發生
日期落在這個帳期窗口內」的 transfer 交易。

### 1. `lib/utils/credit_card_payment.dart`:新增 `attributePaymentsToPeriods`

輸入「由舊到新排序的帳期清單(各自帶自己的淨新增花費)」跟「由舊到新排序
的繳款交易清單」,模擬「目前最舊還有欠款的帳期」指標依序被每筆繳款沖銷
(沖完一期移到下一期,一筆繳款可能沖掉好幾期),回傳每筆繳款「主要沖銷的
帳期」——固定回傳**它開始沖銷的那一期**(最舊的那期),不把同一筆交易拆成
兩半分別顯示在兩個帳期(UI 不用處理「一筆交易金額被切開顯示」的複雜度,
也符合使用者直覺「這筆錢主要是拿去繳哪期帳單」)。純函式,不依賴
Drift/Riverpod,測試在 `test/utils/credit_card_payment_test.dart` 新增 7 個
案例。

### 2. Repository 新增兩個方法(`account_repository.dart` 介面 + `local_account_repository.dart` 實作 + `local_repository.dart` 透傳)

- `getCreditCardPaymentTransactions(accountId)`:這張卡收到的全部繳款交易
  明細(跟既有 `getCreditCardPaidTotal` 同一個查詢範圍——`type='transfer'`、
  `toAccountId=accountId`、排除共享帳本、真·終身不設 cutoff——只是回傳明細
  列而非加總),依入帳歸屬日排序。
- `getCreditCardFirstActivityAt(accountId)`:這張卡「有史以來」第一筆會影響
  帳單口徑的交易(`expense`/`income`/轉入的 `transfer`)入帳歸屬日,沒有任何
  交易時回傳 `null`。用途見下方「開發過程中修正的兩個重複計算陷阱」。

### 3. `lib/providers/credit_card_billing_providers.dart`:新增 `creditCardPaymentPeriodRecordsProvider`

`FutureProvider.family<List<Transaction>, ({accountId, extraIdsKey, billingDay, targetOffset})>`
——回傳 `targetOffset` 這個帳期實際被沖銷到的繳款交易明細:

1. 用 `getCreditCardFirstActivityAt`(合併帳單群組要對每個子帳戶都查,取
   最早的一個)找出模擬要往回展開到多舊的帳期,`priorCarryDue` 固定用 `0`
   當起點(精確值,不是近似——這個 offset 之前保證沒有任何交易)。
2. 模擬範圍是這個起點到「當期」(offset 0),每期的 `newSpend` 用
   `getCreditCardChargedAsOf` 的期末減期初算。
3. 把這張卡(+ 群組子帳戶)全部繳款交易、依入帳歸屬日排序,餵給
   `attributePaymentsToPeriods`。
4. 篩出 `home[txId] == targetOffset` 的交易,依入帳歸屬日新到舊排序回傳。

### 4. `account_detail_page.dart`:「繳款記錄」區塊改吃新 provider

`_buildBillingPeriodTransactionList` 的「一般記錄」不變(還是用既有
`accountBillingPeriodTransactionsProvider` 的日期窗口查詢,剔除
`isPaymentRecord` 判斷式命中的交易);「繳款記錄」改成
`ref.watch(creditCardPaymentPeriodRecordsProvider(...))`,拿不到值時
`_buildBillingRecordsSection` 新增的 `isLoading` 參數只在這個區塊內顯示
spinner,不擋住旁邊已經有資料的一般記錄區塊(「已繳金額」摘要本身是同步
可得的 watermark 計算,不會被這個非同步查詢拖慢)。

## 開發過程中修正的兩個重複計算陷阱

實作過程中用單元測試(`test/providers/credit_card_payment_period_records_provider_test.dart`)
重現使用者的確切場景時,抓到兩版錯誤實作,都是同一個根因的不同表現形式:
**`getCreditCardPaidTotal` 是真·終身加總、完全不設任何日期 cutoff**,任何
「用這個方法在某個時間點算出一個 priorCarryDue 快照,再另外只處理這個時間
點之後的繳款」的設計,都會把同一筆繳款算兩次:

1. **第一版**:`priorCarryDue` 用 `_dueAsOf`(= `getCreditCardChargedAsOf` −
   `getCreditCardPaidTotal`)在目標帳期期初算,`payments` 只挑「日期 ≥ 這個
   期初」的繳款餵給模擬。08/12 的繳款日期晚於 07/11–08/11 期的期初,理論上
   該被排除在 `priorCarryDue` 之外、只在 `payments` 清單處理一次——但
   `getCreditCardPaidTotal` 沒有 cutoff,`priorCarryDue` 這個快照本身**已經**
   把 08/12 這筆繳款算進去了(因為它是終身加總的一部分),`payments` 清單又
   把同一筆繳款再放進去一次,等於扣了兩次。單元測試現象:查詢
   `08/11–09/11` 期時,08/12 這筆繳款同時出現在被沖銷的舊帳期*跟*這個下一期
   的繳款記錄裡。
2. **第二版**:改用 `findEarliestUnpaidPeriodOffset`(「今天呼叫當下,聚合
   欠款不論繳款日期是否為 0」)當模擬起點,`priorCarryDue` 固定 0。這個方向
   對了一半——問題出在「今天聚合欠款是否為 0」是跟 `targetOffset` 無關的
   全域今日快照,拿它決定「模擬要不要往回展開到某個舊帳期」,對同一張卡在
   查詢「較新一期」時會漏掉較舊一期的 `newSpend`,導致較舊一期實際收到的
   繳款在模擬裡被錯誤地提早移到新一期身上,同時歸屬給新舊兩期。單元測試
   現象:一筆足額繳清舊帳期的繳款(`payOld`)先付掉舊帳期,理論上第二筆
   繳款(`payNew`)該歸屬到新的一期——查詢舊帳期本身沒問題,但查詢新一期時
   `payOld`/`payNew` 兩筆都跑出來了。

最終版改用 `getCreditCardFirstActivityAt`(交易本身最早的日期,跟「呼叫
當下是哪一天」「查詢哪個 `targetOffset`」都無關)當模擬起點,對同一張卡的
任何 `targetOffset` 查詢都是同一個、穩定的起點,才徹底避開這個陷阱。這個
教訓記錄在 `creditCardPaymentPeriodRecordsProvider` 的文件註解裡,避免以後
優化效能時又走回「用聚合快照當某個時間點的起點」這條路。

## 刻意排除的範圍

- **不改「已繳金額」/「剩餘帳款」的計算**——這兩個數字本來就已經正確
  (watermark 公式,見 server-parity-fixes.md),這次只是讓「繳款記錄」清單
  跟這兩個已經正確的數字對齊,不是重新設計計算邏輯。
- **不把單筆繳款拆成兩半顯示在兩個帳期**——見上方 `attributePaymentsToPeriods`
  文件註解的取捨說明。實務上這種情境(一筆繳款金額剛好橫跨兩期債務邊界)
  少見,且拆開顯示需要 UI 另外處理「同一筆交易顯示兩個不同金額」的複雜度,
  這次選擇「歸屬到它開始沖銷的那一期」這個簡化但仍然一致的規則。
- **「可繳款」徽章(資產頁,`creditCardBillingBadgeProvider`)沒有改動**——
  複查後確認這個徽章本來就已經用同一套 watermark 公式(`getCreditCardChargedAsOf`
  − `getCreditCardPaidTotal`,終身不設 cutoff)算「最近一次已結帳週期」的
  剩餘應繳金額,不受繳款交易實際發生在哪個日期窗口影響——只要某期真的被
  繳清(watermark 意義上的欠款歸零),徽章本來就會正確消失,不會因為「當期
  (尚未結帳)有日常未出帳消費」誤觸發,已經在單元測試
  `test/providers/credit_card_payment_period_records_provider_test.dart` 的
  兩個情境裡間接驗證過(`payOld`/`payNew` 都在各自的模擬迴圈裡把對應帳期的
  `dueByPeriod` 正確歸零)。使用者回報的「摘要顯示已收到錢、清單卻顯示 0
  筆」矛盾,根因完全在清單這一側,不在徽章/摘要的計算。

## Verification

- `flutter analyze`:涉及的 6 個檔案(`credit_card_payment.dart`、
  `account_repository.dart`、`local_account_repository.dart`、
  `local_repository.dart`、`credit_card_billing_providers.dart`、
  `account_detail_page.dart`)0 新增 issue(既有噪音跟這次改動無關)。
- `flutter test`:全數通過(764 個),含新增
  `test/utils/credit_card_payment_test.dart` 的 7 個 `attributePaymentsToPeriods`
  案例,以及新檔 `test/providers/credit_card_payment_period_records_provider_test.dart`
  的 3 個端到端案例(單卡 2 個 + 合併帳單群組 1 個,用 `BeeDatabase.forTesting`
  + `LocalRepository` + `ProviderContainer` 重現使用者的確切場景,不是純函式
  單元測試——這個 bug 本身橫跨 repository SQL 查詢跟 provider 組裝邏輯,純
  函式測試測不出上面兩個重複計算陷阱)。
- 手動驗證(模擬器/實機)待補:自動化測試涵蓋單卡跟合併帳單群組的資料
  邏輯,但沒有實際點開 UI 核對「繳款記錄」區塊的 loading spinner/空狀態顯示
  跟深色/淺色主題。
