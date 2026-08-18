# 信用卡繳款(MOZE 對標):預設帳期、應繳金額公式、未對帳提醒、群組分攤

日期:2026-08-18
背景:使用者提供 MOZE(`doc.moze.app/credit-card/payment`)信用卡繳款畫面截圖
與三條商業規則(`docs/MOZE_FEATURE_GAP_SD.md` §2.9 在 BeeCount Cloud 側早已
落地的同一組信用卡帳務邏輯,mobile 端當時標記「待排期」),要求 App 端對標
實作:①預設停留在尚未繳清的最早歷史帳期;②「新增還款」預帶金額 = 當期
消費+上期未繳−溢繳−回饋折抵;③新增繳款紀錄時若本期有未對帳交易跳出非
阻擋性提醒;外加專用繳款流程 + 合併帳單主帳戶一次繳款自動分攤到各子卡。

**不改 `Transactions` schema、不改 sync 契約**——繳款仍然是既有的
`type='transfer'` + `toAccountId`,只是新增專用的 UI 流程(預帶金額/備註、
群組分攤),不是發明新的交易類型枚舉值。範圍/風險都比之前的對帳模式
(schema + sync 契約都動了)小很多。

## 1. Repository:`getAccountBalance`/`getCreditCardUsedAmount` 加 `asOf`

**改了什麼**:`lib/data/repositories/account_repository.dart` 兩個方法簽章
加可選具名參數 `DateTime? asOf`(不傳 = 現在,行為完全不變)。
`lib/data/repositories/local/local_account_repository.dart` 內部把寫死的
`final now = DateTime.now();` 改成 `final cutoff = asOf ?? DateTime.now();`,
其餘終身跑動餘額累加邏輯不動。`lib/data/repositories/local/local_repository.dart`
的透傳 wrapper 補上參數轉發。

**為什麼**:`getAccountBalance` 本來就是一個終身跑動餘額計算(信用卡欠款用
負數表示),跟 BeeCount Cloud `credit_card_billing.compute_group_billing` 的
`remaining_due` 是同一個設計語意,只是原本只能算「截至現在」。規則二公式
的「上期未繳」「溢繳」「回饋折抵」三項,只要能對這個既有方法傳入「截至某
帳期結束日」的 cutoff,就會自動正確(income 型『回饋金』分類交易本來就會
被這個迴圈當正項處理,天然抵消欠款),不需要在 UI 層另外手刻加減法。

## 2. `lib/utils/credit_card_payment.dart`(新檔):兩個純函式

- `allocateCardPayment`:照抄 BeeCount Cloud
  `src/services/credit_card_billing.py::compute_card_payment_allocations`
  的分攤規則——金額 ≥ 應繳總和時每個子卡各自拿到付清金額、溢繳另記一筆在
  群組自己身上;金額 < 應繳總和時按比例分攤、最後一筆用減法拿餘數避免
  四捨五入誤差。
- `findEarliestUnpaidPeriodOffset`:規則一的「最早未繳清帳期」掃描,從
  offset=0 往回走,呼叫端注入的 `balanceOwedAsOf(offset)` callback 算每期
  期末的「仍欠款」金額,欠款歸零就停止(找到已清償邊界)。跟 plan 草稿的
  差異:改成 `Function(int offset)` 而不是 `Function(DateTime periodEnd)` +
  另傳 `billingDay`,讓這個檔案不用 import `card_reward_period.dart`,呼叫端
  (provider)自己把 offset 轉成週期日期,職責更乾淨。
- `endOfDay`/`startOfDayExclusivePrior`:cutoff 正規化 helper,比照既有
  `getAccountTransactions` 的 `endDate` 慣例(含當天全部)。

不依賴 Drift/Riverpod,純函式方便單元測試(`test/utils/credit_card_payment_test.dart`,
11 個案例,鏡射 Cloud `tests/test_credit_card.py` 的分攤情境)。

## 3. `lib/providers/credit_card_billing_providers.dart`(新檔)

`defaultBillingPeriodOffsetProvider`(規則一用)跟 `accountBalanceAsOfProvider`
(規則二「上期欠款」/「剩餘帳款」/新增還款預帶金額共用)兩個
`FutureProvider.family`,都把合併帳單群組的子帳戶 id 加總後呼叫上面的
repository 方法。`accountBalanceAsOfProvider` 回傳值的號位跟既有
`_buildBillingSummaryRows` 的 `remaining`(負值=欠款)一致,不是「欠款轉正」
——避免呼叫端要記兩套號位慣例。

## 4. `account_detail_page.dart`:預設帳期 + 彙總卡片修正 + 列表拆分

**規則一(預設帳期)**:新增 `_billingPeriodOffsetResolved` state。信用卡/
`account_group` 分支在這個 flag 為 false 時,watch `defaultBillingPeriodOffsetProvider`,
拿到值前顯示 loading(避免「先跳最新一期再跳到未繳清帳期」的畫面閃爍),
拿到值後用 `addPostFrameCallback` 套用並鎖定 flag(之後使用者手動翻頁不會
被覆蓋)。**已知邊界情況**:`children` 依賴 `allAccountsStreamProvider`,若
這個 stream 在頁面剛開啟時還沒吐出資料,defaultOffset 會先按「沒有子帳戶」
算一次;本地優先架構下這個 stream 通常已經有快取資料,實務影響低,沒有
特別處理(對應 plan 裡記錄的已知取捨)。

**規則二(彙總卡片)**:`_buildBillingSummaryRows` 的 `priorBalance`/`remaining`
改吃 `accountBalanceAsOfProvider` 算出的快照(`priorBalance` 傳
`startOfDayExclusivePrior(period.start)`,`remaining` 傳
`endOfDay(period.end)`),取代原本硬編碼 0 跟手動加減法。新增「回饋折抵」列
(只在本期有 income 型『回饋金』分類交易時顯示,`isRewardCategoryName` 復用
`lib/utils/reconciliation.dart` 既有函式)。兩個新 provider 值到達前,對應列
顯示小 spinner,不整卡擋 loading(新增花費/已繳金額本來就是同步可算的)。

**列表拆分**:`_buildBillingPeriodTransactionList` 依既有「轉入這張卡/群組
視為還款」判斷式(跟帳單彙總卡片 `paidIn` 同一套)把週期內交易分成
「繳款記錄 (N)」/「一般記錄 (N)」兩個 `SectionCard`(新增
`_buildBillingRecordsSection` helper,渲染邏輯跟既有
`_buildTransactionListBody` 的 tile 渲染一致,但不reuse 那個方法——它是
非信用卡帳戶分頁列表也在用的共用方法,拆分邏輯只在信用卡帳期視圖需要,
不想影響到那邊)。

**規則三(未對帳軟提醒)**:繳款記錄 `+` 按鈕(`_onAddPaymentRecord`)最前面
檢查目前選取帳期的 `reconciledAt == null` 筆數(跟彙總卡片「對帳筆數」列
同一份資料,口徑一致),有未對帳筆數時彈出 `AlertDialog`(取消/繼續繳款),
選「繼續繳款」直接放行,不做任何標記——純提醒,不阻擋。

**新增還款入口**:一般記錄 `+` 複製 `account_reconciliation_page.dart`
「新增遺漏的交易」既有模式(`TransactionEditorPage(initialKind:'expense', ...)`)。
繳款記錄 `+` 通過規則三檢查後:單卡直接開
`TransactionEditorPage(initialKind:'transfer', initialToAccountId:, initialAmount:, initialNote:)`
(這個頁面本來就支援轉帳分頁的這些預帶欄位,不需要新頁面);合併帳單群組
(`children.isNotEmpty`)改開下面第 5 節的新頁面。

## 5. `lib/pages/account/credit_card_group_payment_page.dart`(新頁面)

進頁面對每個子卡呼叫 `getCreditCardUsedAmount(childId, asOf: 帳期結束日)`
算應繳金額,來源帳戶選擇器複用既有 `AccountCardPicker`(這個元件本來就已經
排除所有 `account_group` 類型帳戶,不用另外加過濾條件,只需要多傳
`excludeAccountId: 這個群組自己`)。總繳款金額輸入框變動時即時用
`allocateCardPayment` 重算分攤預覽。送出時把分攤結果轉成
`List<TransactionsCompanion>`(每筆 `type='transfer'`),一次呼叫既有
`repo.insertTransactionsBatch`(單一 db transaction + 逐筆
`recordLedgerChange`,不需要新的 repository 方法)。

**刻意排除的範圍**:
- 跨幣別群組分攤(子卡幣別不同時不做匯率換算)——來源帳戶用
  `filterCurrency: currencyCode` 篩選,同幣別假設。
- 多筆繳款組成一個可整批復原的「批次」概念——送出後每筆 transfer 各自獨立
  可個別編輯/刪除,跟一般記帳一致,不建立額外的批次關聯實體。
- 這次沒有做 Cloud 端「自動扣繳」(`credit_card_autopay`)的對應——那是另一
  個獨立範圍,依賴 App 端還沒有的排程機制。

## 6. l10n

只改 `app_en.arb` + `app_zh_TW.arb`(`[[feedback_l10n_policy_change]]`,不碰
`app_zh.arb`/`app_ko.arb`)。新 key:`billingSummaryRewardDeduction`、
`billingPaymentRecordsTitle`/`billingGeneralRecordsTitle`、
`billingUnreconciledPaymentWarningTitle`/`Message`、`continuePayment`、
`creditCardGroupPaymentPageTitle` 系列(6 個)。

## Verification

- `dart run build_runner build`:通過,無 schema diff(預期——這次沒有動
  `db.dart`)。
- `flutter analyze`:0 error(既有噪音跟這次改動無關,新增/改動的檔案本身
  0 issue)。
- `flutter test`:全數通過,含新增
  `test/utils/credit_card_payment_test.dart`(11 例:`allocateCardPayment`
  足額付清+溢繳歸群組/剛好付清/不足額按比例+最後一筆吃餘數/沒人欠錢/金額
  <=0/多子卡舍入誤差 6 例,`findEarliestUnpaidPeriodOffset` 已清償/連續兩期
  未繳/只有當期未繳/maxLookback 到頂 4 例)。
- 手動驗證(模擬器/實機)待補:開一張有欠款的獨立信用卡跟一張合併帳單主
  帳戶,依 plan 的 Verification 章節逐項核對——尤其是深色/淺色主題、
  zh-TW/en 語言切換、群組分攤「足額+溢繳」「不足額按比例」兩種情境送出後
  的交易筆數跟金額。
