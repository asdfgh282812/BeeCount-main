# 零股最低手續費 + 報價卡在前一交易日

日期:2026-10-03
接續 `2026-09-28-stock-fee-reconciliation.md`。跨 repo:本 repo(App)+ BeeCount
Cloud(server + Web),Cloud 端見 `BeeCount-Cloud/docs/STOCK_HOLDINGS_SD.md` §8.1。

## 使用者回報

0050 持有 50 股,付出成本 4,878。永豐庫存顯示現價 112.8、現值 5,627、預估損益
749(15.35%)。App 和 Web 都顯示現價 112.90(報價時間 10/1 13:30)、預估手續費 20、
淨值 5,620、損益 742(15.21%)。

拆開來是兩個問題:

1. **最低手續費**:券商算 ⌊5,640 × 0.1425%⌋ = 8。我們套了台股預設最低手續費 20。
   永豐的整股最低 20 元、零股最低 1 元。使用者 9/28 那筆買進手續費 6 元
   (⌊4,872 × 0.1425%⌋)也是同一條規則。
2. **報價停在 10/1**:10/2 已經收盤(Yahoo 有 112.8),但 server 快取還是 10/1 的
   證交所收盤價。詳見下方。

套用兩個修正後:5,640 − 8 − 5 = 5,627,損益 749,跟券商一致。

## 入口

- **費用設定**(資產 → 投資理財帳戶 → 持股 →「費用設定」;Web:投資 → 帳戶卡
  →「費用設定」):台股原本的「最低手續費」改名為「整股最低手續費」(預設 20),
  新增「零股最低手續費」(預設 1)。
- 持股詳細頁的「預估賣出手續費」、Web 持股表的「預估淨值」,以及新增交易時預填的
  手續費和交易稅,都會套用。

## 1. 整股 / 零股分開計算(`InvestmentSettings.orderParts`)

台股整股和零股是兩張不同的委託單。有給股數時,手續費和交易稅會拆成「整股部分 +
零股部分」,各自取整、套各自的最低手續費,再相加。例:1,050 股 = 1,000 股整股 +
50 股零股。

- 新設定 key `oddLotFeeMin`(TW/TWO 預設 1)。沒設時退回 `feeMin`,所以其它市場
  行為不變。
- `suggestFee` / `suggestSellTax` 多了選填的 `shares`。目前有傳股數的地方:
  `estimateSell`(庫存預估淨值),以及 `StockTradeEditorPage` 的手續費和交易稅預填。
- **跟 ETF 稅率一樣是獨立欄位,不是覆寫 `feeMin`**。很多人在費用設定把最低手續費
  明確填成 20;共用同一個欄位的話,零股會一直被算成 20。
- **定期定額不變**:`stockDcaOrder` 沒傳股數,繼續用規則自己的 `stockFeeMin`(或帳戶
  的 `feeMin`),是跟 Cloud 約定好的契約,見 `project_stock_dca_contract`。
- 只拆整股和零股。如果持股是好幾筆零股買進,券商會逐筆計算再加總,我們是用總股數
  算一次,遇到取整時可能差 1 元。

## 2. 報價卡在前一交易日(Cloud `services/securities/quotes.py`)

原因:

- 證交所 OpenAPI(`STOCK_DAY_ALL`)常常到晚上、甚至隔天才更新。2026-10-03 凌晨查
  的時候還是 10/1 的資料。
- `needs_refresh` 只看 `fetched_at`(多久沒抓),不看報價本身是哪天的。收盤後才抓到
  的舊資料,`fetched_at` 很新,12 小時內都不會再補抓。
- 收盤排程在收盤後 3 小時的重試窗口過了以後就算「完成」,即使資料還是舊的也一樣
  (Yahoo 優先的修正 `de7530c` 是 10/2 17:32 才 commit,如果是窗口過後才部署,就沒
  機會再抓)。

修法:

- `markets.latest_session_date`:現在應該看得到的最新交易日。交易日開盤後是今天,
  開盤前和週末是前一交易日。
- `needs_refresh`:報價日期早於最新交易日時,距離上次抓超過 30 分鐘
  (`BEHIND_RETRY_TTL`)就再抓一次。
- `_close_done`:重試窗口過了資料還是舊的,就改成每 30 分鐘再試一次到當天結束,
  不再直接放棄。
- 國定假日沒有建行事曆,會被當成交易日,多重試幾次,抓到的仍是前一交易日收盤,
  結果正確。

App 和 Web 都是向 server 拿報價,所以這部分只改 Cloud。

## 三端一致

App `lib/models/investment_settings.dart`、Cloud `services/securities/trade_fees.py`
(`order_parts`)、Web `packages/web-features/src/lib/investment.ts`(`orderParts`)用
同一組數字測:

- 0050 50 股 @112.8:手續費 8、稅 5、淨值 5,627、損益 749。
- 只設 `feeMin: 20` 時零股仍是 8;設 `oddLotFeeMin: 20` 才是 20。
- 1,050 股 @112.8(2330):手續費 160 + 8、稅 338 + 16。

App `investment_settings_test.dart`、Cloud `tests/test_trade_fees.py`、Web
`investmentFees.test.ts`。報價:Cloud `tests/test_stock_holdings.py`
`test_quote_behind_latest_session_*`、`test_close_job_keeps_retrying_*`。

## 部署

- 先部署 Cloud:報價修正只在 server;`normalize_investment_settings` 要先認得
  `oddLotFeeMin`,不然 App/Web 存的值會被丟掉。
- 舊版 App 看不懂 `oddLotFeeMin`,讀到時會忽略。在舊版 App 存一次費用設定,會把這個值
  洗掉,回到預設 1 元(多數人就是用預設值,影響不大)。
