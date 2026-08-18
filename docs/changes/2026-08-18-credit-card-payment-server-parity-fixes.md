# 信用卡繳款:4 個對齊 Server 端的 bugfix(帳單算法/繳款清單/回饋期別/可繳款徽章)

日期:2026-08-18
背景:延續 [2026-08-18-credit-card-payment-moze-parity.md](2026-08-18-credit-card-payment-moze-parity.md)
的 MOZE 對標實作,使用者實機測了一張真實信用卡帳戶後回報 4 個「App 跟
Server(BeeCount Cloud)算出來的數字/畫面對不上」的問題。用 Explore agent
讀了 BeeCount Cloud(`/Users/andy/BeeCount-Cloud`)`src/services/credit_card_billing.py`
的 `compute_cycle_period_billing`/`compute_group_billing`、
`src/routers/read/{ledgers,workspace}.py`、`src/services/card_rewards.py`/
`credit_card_reminders.py` 的實際原始碼(不是猜行為),逐條核對後發現 App
端這次的帳單彙總計算,結構上就跟 Server 端的公式不一樣,不是單純的日期
邊界誤差。

## 1. 帳單彙總計算對不上(核心 bug,140 元誤差只是症狀之一)

**改了什麼**:新增 `AccountRepository.getCreditCardChargedAsOf`/
`getCreditCardPaidTotal`(`account_repository.dart` 介面 + `local_account_repository.dart`
實作 + `local_repository.dart` 透傳),取代信用卡帳單口徑原本借用的
`getAccountBalance`/`getCreditCardUsedAmount`。`credit_card_payment.dart` 新增
純函式 `creditCardDueAsOf({charged, paidTotal}) => max(charged - paidTotal, 0)`。
`credit_card_billing_providers.dart` 的 `accountBalanceAsOfProvider`/
`defaultBillingPeriodOffsetProvider`,以及 `credit_card_group_payment_page.dart`
的子卡應繳金額,全部改用這組新方法。

**為什麼**:Server 端 `compute_cycle_period_billing` 的欠款公式是純交易導向的
`charged_as_of(cutoff) = Σexpense − Σincome`(`_ATTR_DATE <= cutoff`,終身無
下界)減去 `paid_total = Σ transfer.amount(toAccountId=這張卡)`(**真·終身,
完全不設 cutoff**——不論繳款發生在哪個帳期,一律先套用在最早未清償的帳期
上,FIFO watermark),兩者相減後 floor 在 0。這個公式裡**沒有** `initialBalance`
/ 轉出(transfer 作為 accountId)/ `adjustment` 型交易的位置。但 App 原本的
`accountBalanceAsOfProvider` 是直接呼叫 `getAccountBalance(asOf:)`——那是給
一般資產帳戶用的「終身跑動餘額」,語意上會把 `account.initialBalance`
(信用卡帳戶編輯頁本來就有這個欄位可填)、轉出這張卡的 transfer、
`adjustment` 型交易都混進來,這些在 Server 端的信用卡帳單公式裡全部不存在,
混進來就會讓 App 算出的欠款比 Server 多或少。另外原本的 `transfersIn` 查詢
也用同一個 `cutoff` 上界綁死(`happenedAt <= cutoff`),等於「已繳金額」只認
「在這個帳期結束前繳的錢」——但 Server 的 `paid_total` 是不設 cutoff 的終身
加總,晚繳的錢一樣會回頭沖銷更早那期的欠款。这两处差異合起来才是使用者
回報「新增花費 -7,477、上期欠款 +0,但剩餘帳款卻變成 -7,617」的根因。

`getCreditCardChargedAsOf` 保留了「asOf 若晚於現在一律 clamp 到現在」的
既有防呆(即使明確傳入未來時間點),對齊 Server `min(cycle_end_dt, now)` 的
「本期還沒結束,不能把還沒發生的週期性交易算進去」邏輯。

**連帶修正**:`_buildBillingSummaryRows` 的「新增花費」原本只加總 `expense`,
沒有扣掉本期 `income`(含回饋金),跟 Server `new_spend` 的
`Σexpense − Σincome` 公式不一致(這次一併補上,`rewardThisPeriod` 的顯示
邏輯不變,純粹是透明度用的子項)。「已繳金額」原本是「本期窗口內轉入金額
的字面加總」,改成鏡射 Server 的 `paid_in_cycle = total_due - remaining_due`
(從 watermark 反推),因為使用者可能在別的帳期繳款、FIFO 回頭沖銷這期,
字面加總會跟 Server 顯示的數字對不上——這正是問題 2 的另一半根因(見下)。

## 2.「繳款記錄」清單顯示 0 筆,但 Server 有記錄

**結論**:查證 Server 端(`routers/read/ledgers.py::get_account_statement`)後,
發現「繳款記錄清單」本來就是**按繳款交易自己的日期落在哪個帳期**過濾
(`attr_date > cycle_start_dt AND <= cycle_end_dt`),這跟第 1 點修的「剩餘
帳款」watermark 公式是兩個刻意不同的口徑——繳款清單答的是「這筆錢是哪天
繳的」,剩餘帳款答的是「欠款有沒有被沖銷,不管沖銷的錢是哪天繳的」。App
端 `_buildBillingPeriodTransactionList` 的 `isPaymentRecord` 判斷式
(`type=='transfer' && toAccountId in ids`)跟查詢日期窗口本身都是正確的,
沒有額外的過濾條件 bug。

實務上使用者看到「這期繳款記錄 0 筆、但剩餘帳款仍顯示有欠款」的畫面,常常
是因為**第 1 點的 bug 讓「預設帳期」(規則一)沒有正確跳過已經被 FIFO
沖銷掉的舊帳期**——`defaultBillingPeriodOffsetProvider` 這次也一併換成新的
watermark 公式(見上),修正後預設停留的帳期會正確反映「哪一期還真的欠
錢」,連帶讓「這期沒有繳款記錄」不再是一個看起來矛盾的畫面。沒有另外改動
繳款清單本身的查詢邏輯。

## 3. 紅利回饋卡片沒有跟著選取的帳期換

**改了什麼**:`cardRewardAccountSummaryProvider`(`card_reward_rule_providers.dart`)
family key 加上 `offset` 欄位,`_summarizeRuleWindow` 呼叫改傳這個值,不再
寫死 `0`。`account_detail_page.dart::_buildRewardSummaryCard` 呼叫時傳入
`offset: _billingPeriodOffset`(跟帳單彙總卡片的期數導覽同一個 state)。

**為什麼**:原本這個 provider 固定用 offset 0(規則以自己的 interval 算,
不管使用者在彙總卡片翻到哪一期),使用者截圖顯示選取 `2026/07/05–08/05`
時紅利回饋區塊卻顯示 `2026/08/05–09/05` 的回饋——因為 offset 0 永遠對應
「今天所在的當期」,不是「使用者正在看的那期」。改完後翻頁到舊帳期,回饋
卡片會跟著顯示那一期(依規則自己的 interval,billing_cycle 一顆週期/
calendar_month 拆自然月)套用的回饋,對齊 Cloud
`services/card_rewards.py::_resolve_periods` 用同一個 `period_offset` 貫穿
的設計。**未驗證項**:Cloud 網頁版前端呼叫卡片回饋 API 時會做
`period_offset = cycleOffset - 1` 的偏移調整(Cloud 內部文件註解提到「兩個
端點之間曾經有過 off-by-one」)。App 端的 `_billingPeriodOffset` 本來就是
直接比照 Cloud 帳單彙總 `cycle_offset` 的語意定義的(`card_reward_period.dart`
文件註解),這次選擇**原樣傳遞、不做 -1 調整**——因為那個偏移是 Cloud 網頁版
自己兩個獨立端點之間的歷史校正,不代表 App 端 `billingCyclePeriod` 跟
Cloud `card_rewards.py` 內部用的 `billing_cycle_containing`/`shift_cycle` 之間
天然就有一樣的偏移。這個假設沒有實機資料可以驗證(需要一張有啟用中回饋
規則、且有跨帳期歷史交易的卡才能觀察),記錄在這裡供之後如果使用者回報
回饋期數還是對不上時,第一個該懷疑的地方。

## 4. 帳戶列表補上「可繳款」徽章

**新增**:`credit_card_billing_providers.dart` 新增
`creditCardBillingBadgeProvider`,`accounts_page.dart::_AccountCard` 新增
`_buildBillingDueBadge`,渲染在帳戶名稱列(比照既有「已隱藏」灰標的位置跟
樣式,改用 error 色)。新 l10n key `creditCardBillingDueBadge`("可繳款
截止日 {date}" / "Payment due {date}")。

**判斷邏輯**(鏡射 Cloud `routers/read/workspace.py::list_workspace_accounts`
附加 `billing_due_date`/`billing_remaining_due` 欄位的條件):
- 只在 billing-root(獨立信用卡,或合併帳單主帳戶 `account_group`)顯示,
  掛靠某個主帳戶的子卡(`parentAccountId != null`)不重複顯示。
- 用「最近一次已結帳週期」(新增 `card_reward_period.dart::mostRecentlyClosedBillingOffset`
  ——offset 0 的 `end` 恆 >= 今天,只有結帳日當天才等於今天,其餘日子都要
  退回 offset -1 才是「已結帳」的那期)的剩餘應付金額,用第 1 點同一組
  `getCreditCardChargedAsOf`/`getCreditCardPaidTotal` 算。
- 條件單純是 `remainingDue > 0.01`,**沒有**額外的「距截止日還剩幾天」時間
  窗口——Cloud 這個欄位本來就是只要有欠款就顯示,不是接近到期才顯示(那是
  另一個獨立機制,`credit_card_reminders.py` 的推播提醒,只在剛好 7 天前/
  當天/逾期時觸發一次性推播,跟這個列表徽章是兩件事,這次只做列表徽章)。

**刻意排除的範圍**:使用者原文提到「標籤及角標數字」,「角標數字」比照
一般 App 常見的未讀數字紅點——但 Cloud 端沒有任何欄位對應「有幾筆待繳」
之類的計數語意(只有 `billing_due_date`/`billing_remaining_due` 兩個純量
欄位),没有 Server 端依據可以照抄一個角標數字出來代表什麼,所以這次只做
了文字徽章(「可繳款 截止日 X/X」),角標數字留白,避免憑空發明一個
Server 端不存在對應語意的 UI 元素。

## Verification

- `dart run build_runner build`:無 schema diff(這次沒有動 `db.dart`)。
- `flutter analyze`:0 error(逐一確認新改動的檔案本身 0 issue,詳見
  `git diff` 涉及的 10 個檔案跑 `flutter analyze` 的輸出,其餘 835 筆都是
  改動前就存在、跟這次無關的既有噪音)。
- `flutter test`:752 個測試全數通過(既有 745 個 + 這次新增 7 個:
  `creditCardDueAsOf` 4 例、`creditCardPaymentDueDate` 3 例,新檔
  `test/utils/card_reward_period_test.dart`)。`mostRecentlyClosedBillingOffset`
  依賴 `DateTime.now()`(比照 `billingCyclePeriod` 本身也沒有可注入時鐘的
  參數),沒有另外補測試,风险判斷:純三行邏輯疊在已經有測試覆蓋的
  `billingCyclePeriod` 之上,面比較小。
- 手動驗證(模擬器/實機)待補,尤其是第 3 點標注的未驗證假設(回饋期數
  offset 對齊)跟第 4 點的徽章視覺(深色/淺色主題、zh-TW/en 切換)。
