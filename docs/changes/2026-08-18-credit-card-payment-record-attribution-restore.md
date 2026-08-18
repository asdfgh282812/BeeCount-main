# 「繳款記錄」小節恢復 FIFO 期別歸屬——範圍收窄到只影響這個顯示區塊

日期:2026-08-18
背景:直接延續同一天稍早的
[credit-card-reconciliation-cloud-parity-fix.md](2026-08-18-credit-card-reconciliation-cloud-parity-fix.md)
——那份文件用 BeeCount Cloud 正式資料庫核對後,把「繳款記錄」的 FIFO 期別
歸屬(`attributePaymentsToPeriods`)整個撤回,改成跟對帳模式一樣的純日期
窗口過濾,理由是「Cloud `get_account_statement` 本來就沒有歸屬概念」。
使用者這次用「星展信用卡」帳戶詳情頁的實測截圖明確推翻了這個結論:
`2026/08/11–09/11` 這期的「繳款記錄」小節顯示兩筆繳款(819、5744,交易
日期都是 08/12,落在這期窗口內),但使用者的原意是「這兩筆錢是繳去年
`2026/06/11–07/11`/`2026/07/11–08/11` 這兩期的帳單」——「雖然是在
8/11–9/11 這期繳費,但我繳的是上一期的費用,所以繳款記錄應該放到
7/11–8/11」。也就是說:**對帳模式(`get_account_statement` 純日期窗口)
維持 Cloud 的既有行為不變是對的,但「繳款記錄」這個顯示區塊使用者要的是
App 自己的、更符合直覺的歸屬邏輯,不是照搬 Cloud 字面行為**——這兩者
在這次之前被誤認為必須是同一套邏輯。

## 改動範圍:只有「繳款記錄」小節,其它全部維持 Cloud 對齊不變

- 「對帳模式」(`AccountReconciliationPage`/`AccountReconciliationSection`/
  `accountStatementTransactionsProvider`)——**不變**,繼續跟 Cloud
  `get_account_statement` 逐筆對齊(見 parity-fix 文件的驗證表)。
- 帳單彙總卡片的「已繳金額」/「剩餬帳款」/「新增花費」——**不變**,繼續用
  watermark 公式(`getCreditCardChargedAsOf`/`getCreditCardPaidTotal`)。
- 帳單週期交易列表的「一般記錄」——**不變**,繼續用
  `accountStatementTransactionsProvider` 的純日期窗口,只是排除掉繳款類的
  transfer。
- **只有「繳款記錄」小節**(`account_detail_page.dart` 信用卡「交易明細」
  tab 裡的「繳款記錄 (N)」卡片)改回依 FIFO 模擬「這筆繳款實際沖銷哪一期
  舊欠款」來分桶,不是按交易自己的入帳歸屬日落在哪個窗口。

## 改動內容

### 1. `lib/utils/credit_card_payment.dart`:恢復 `attributePaymentsToPeriods`

跟 2026-08-18 稍早
[credit-card-payment-attribution-last-period-fix.md](2026-08-18-credit-card-payment-attribution-last-period-fix.md)
定案的「最後沖到的那一期」規則相同(`lastTarget`,不是「開始沖銷的那
一期」)：模擬「目前最舊還有欠款的帳期」指標依序被每筆繳款沖銷,回傳
每筆繳款主要沖銷到的帳期。純函式,`test/utils/credit_card_payment_test.dart`
新增 7 個案例,其中一個直接鏡射星展信用卡真實金額(2304/4259 兩期,
819/5744 兩筆繳款),斷言 819 歸屬到 06/11–07/11(offset -2)、5744 歸屬到
07/11–08/11(offset -1)——**跟使用者這次反饋的方向一致**(819/5744 都不該
留在 08/11–09/11)。

### 2. Repository 新增回兩個方法

`account_repository.dart` 介面 + `local_account_repository.dart` 實作 +
`local_repository.dart` 透傳:

- `getCreditCardPaymentTransactions(accountId)`:這張卡收到的全部繳款交易
  明細(跟既有 `getCreditCardPaidTotal` 同一個查詢範圍,只是回傳明細列),
  依入帳歸屬日排序。
- `getCreditCardFirstActivityAt(accountId)`:這張卡「有史以來」第一筆會
  影響帳單口徑的交易入帳歸屬日,當模擬展開的穩定起點(不能用聚合快照
  代替,理由見下方連結文件的踩坑記錄)。

### 3. `lib/providers/credit_card_billing_providers.dart`:恢復 `creditCardPaymentPeriodRecordsProvider`

`FutureProvider.family<List<db.Transaction>, ({accountId, extraIdsKey,
billingDay, targetOffset})>`——邏輯跟撤回前完全一致(見
[credit-card-payment-period-attribution-fix.md](2026-08-18-credit-card-payment-period-attribution-fix.md)
的「核心改動」小節,這裡不重複列步驟),包含當初踩過的兩個重複計算陷阱
的最終解法(用 `getCreditCardFirstActivityAt` 而非任何聚合快照當模擬起點)。

### 4. `account_detail_page.dart`:「繳款記錄」小節改吃新 provider

`_buildBillingTransactionList` 額外 watch `creditCardPaymentPeriodRecordsProvider`
(`targetOffset: _billingPeriodOffset`),把結果連同既有 `transactions`
一起傳給 `_buildBillingPeriodTransactionList`；「一般記錄」不變,還是用
`accountStatementTransactionsProvider` 的 `transactions` 剔除掉
`isPaymentRecord` 命中的交易；「繳款記錄」的 `paymentRecords` 改成從新
provider 的 `AsyncValue` 取值,`_buildBillingRecordsSection` 恢復
`isLoading` 參數,只在「繳款記錄」這個區塊內顯示 spinner,不擋住旁邊的
「一般記錄」。

## 為什麼這次不是走回頭路

同一天稍早的 parity-fix 文件把 FIFO 歸屬撤回,論證是「Cloud 沒有這個概念,
不該自創」。這次恢復不是推翻那個論證,而是**縮小了它的適用範圍**:
Cloud 沒有歸屬概念這件事只約束「跟 Cloud 對得上的部分」(對帳模式、
彙總數字)——這些繼續保持 Cloud parity。但「繳款記錄」這個 UI 小節本來
就是純顯示層的分組方式,不是任何 Cloud API 回傳的資料結構,使用者作為
這個功能的實際使用者明確表達了他要的分組邏輯,這屬於產品行為決策,不是
「跟 Server 對不對得上」的技術正確性問題。兩者的判準本來就不同,之前
誤把「不該自創對帳邏輯」的教訓過度延伸到了「繳款記錄要怎麼分組顯示」
這個純 App 端的產品決定上。

## 測試

- `test/utils/credit_card_payment_test.dart`:恢復 `attributePaymentsToPeriods`
  測試群組(7 例,含星展信用卡真實金額案例)。
- `test/providers/credit_card_payment_period_records_provider_test.dart`
  (新檔):端到端案例,用 `BeeDatabase.forTesting` + `LocalRepository` +
  `ProviderContainer`,以「現在」為基準反推三個帳期的日期範圍重建星展
  信用卡場景,斷言 819/5744 分別出現在 offset -2/-1 的查詢結果裡、offset 0
  (當期)查不到任何繳款記錄。
- `flutter analyze`:0 新增 issue(既有 835 筆噪音跟這次改動無關)。
- `flutter test`:763 個測試全數通過(既有 755 個 + 這次新增 8 個)。
- 手動驗證(模擬器/實機)待補——這台機器沒有可用的 iOS Simulator/Android
  SDK(同前幾份文件的已知限制)。

## 刻意不動的部分

同 [credit-card-payment-period-attribution-fix.md](2026-08-18-credit-card-payment-period-attribution-fix.md)
「刻意排除的範圍」一節——不改「已繳金額」/「剩餬帳款」的計算、不把單筆
繳款拆成兩半顯示在兩個帳期、「可繳款」徽章不受影響。這次額外確認:對帳
模式(`accountStatementTransactionsProvider`)、帳單彙總卡片維持
`credit-card-reconciliation-cloud-parity-fix.md` 定案的純日期窗口/watermark
邏輯,完全不受這次改動影響。
