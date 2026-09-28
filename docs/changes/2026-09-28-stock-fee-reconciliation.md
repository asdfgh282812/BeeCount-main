# 股票費用跟券商對帳單對齊 + 自動帶入現價

日期:2026-09-28
接續 `2026-09-28-stock-holdings.md`(Phase 1)、`2026-09-28-stock-dividends.md`(Phase 2)。
跨 repo:本 repo(App)+ BeeCount Cloud(`/Users/andy/BeeCount-Cloud`,server + Web)。
Cloud 端見 `BeeCount-Cloud/docs/STOCK_HOLDINGS_SD.md` §8。

使用者拿永豐證券的對帳單比,發現四個問題:

1. 賣 ETF(0050)時證交稅被算成 0.3%,多了 3 倍(ETF 法定 0.1%)。
2. 零股 50 × 97.45 = 4,872.5 被四捨五入成 4,873,加手續費後跟券商差 1 元。
3. 庫存的市值/未實現損益是毛額,券商顯示的是「扣掉預估賣出稅費」的淨額。
4. App 的投資市值卡顯示「1 檔尚無報價」,Web 同一檔卻有報價;新增交易時也
   不會帶入現價。

## 入口

- **費用設定**(資產 → 投資理財帳戶 → 持股 →「費用設定」;Web:投資 → 帳戶卡
  →「費用設定」):台股多了「ETF 交易稅率」「債券 ETF 交易稅率」,原本的「賣出
  交易稅率」在台股改叫「普通股交易稅率」;多一個開關「未實現損益扣除預估賣出
  費用」(預設開)。
- **新增股票交易**:選/輸入代號後自動帶入現價(下方有「已帶入目前報價(收盤價
  …)」提示);賣出時交易稅下方顯示「證交稅率 0.1%(ETF)」。
- **持股詳細頁**:多了「預估賣出手續費 / 預估交易稅 / 預估變現淨值」三行。
- **資產頁投資市值卡、持股分頁上方、Web 投資頁**:未實現損益旁標示「已扣預估
  賣出費用」與預估變現淨值;Web 持股表多一欄「預估淨值」。

## 1. 證交稅依標的類型(`lib/services/investment/markets.dart::securityKindOf`)

只看代號、不查資料庫:台股(TW/TWO)代號 `00` 開頭是 ETF(0050、00878、00631L),
其中結尾 `B` 是債券 ETF(00679B);其它都是普通股。其它市場不分類型,一律用
`sellTaxRate`。

`InvestmentSettings` 新增 `etfSellTaxRate`(預設 0.001)、`bondEtfSellTaxRate`
(預設 0)。`sellTaxRate` 在台股代表「普通股」。**分成三個欄位而不是一個「覆寫
稅率」**,是因為多數人會在費用設定裡把 `sellTaxRate` 明確填成 0.3%;如果只有
一個欄位,使用者設定一定蓋過 ETF 的預設值,原本的 bug 就修不掉。

不處理的情況(會被當成普通股或 ETF,需要時自己改交易稅欄位):當沖(0.15%)、
ETN(`02` 開頭,法定 0.1%,目前會被當普通股)、權證、REITs。

## 2. 台幣價金無條件捨去(`InvestmentSettings.gross` / `roundMoney`)

成交價金、手續費、交易稅在 TWD/JPY/KRW 一律**無條件捨去**到整數;其它幣別四捨
五入到分。捨去前先四捨五入到小數 6 位,避免 1000 × 600.1 = 600099.99999… 被捨成
600,099。影響:

- `stockTradeAmount` / `stockTradeTxFields`(多一個 `currency` 參數):0050 買 50 股
  @97.45、手續費 6 → 轉帳 4,872 + 手續費 6,明細成本 4,878。
- **美股零碎股的價金現在也四捨五入到分**(以前保留 6 位小數)。例:0.0055 股 ×
  341.07 = 1.875885 → 1.88。`stock_trade_repository_test.dart` 的零碎股再投入測試
  跟著改。
- `HoldingView.marketValue` 也用同一個取整,帳戶列表不會出現「2,702,632.5」。
- **舊資料不會自動重算**。已經記錄的交易要重新開啟並儲存一次,才會套用新的
  取整方式。

## 3. 預估變現淨值(`InvestmentSettings.estimateSell`、`HoldingView`)

預估手續費 = max(⌊市值 × 費率 × 折扣⌋, 最低手續費);預估交易稅 = ⌊市值 × 標的
稅率⌋;淨值 = 市值 − 兩者。`HoldingView` 新增 `sellEstimate` / `netValue` /
`valuation` / `pnlAfterSellCosts`,`unrealizedPnl` 改用 `valuation`(開關開著用淨值,
關掉用毛市值)。`allHoldingsProvider` 現在會讀帳戶的 `investmentSettingsJson` 傳給
每一檔。`InvestmentSummary` 多了 `netValue` / `valuation` / `pnlAfterSellCosts`。
「市值」本身仍是毛額(股數 × 現價),淨值另外顯示。

開關存在帳戶的 `investmentSettings.pnlAfterSellCosts`,**預設開、只有關掉才存
`false`**,會同步到 Cloud,讓 Web 算出一樣的數字。

## 4. 報價與現價帶入(`securities_providers.dart::QuoteRefreshNotifier`)

**原因**:App 以前只在三個時機抓報價:帳戶頁 initState、App 回到前景、持股頁
下拉。如果交易是在 Web 新增的,App 打開資產頁時 sync 可能還沒把它拉回來。等
sync 拉回新代號,已經沒有下一個觸發點,要到下次切回前景才會有市值。Web 每次
開頁都向 server 拿持股加報價,所以沒有這個問題。

**修法**:`quoteRefreshProvider` 建立時監聽 `stockTradesProvider`
(`onTradesChanged`)。明細一有變動,就檢查有沒有「有持股但本地沒報價」的代號,
有的話立刻補抓。同一個代號 10 分鐘內只試一次,避免 server 本來就抓不到的代號
一直重打。

**現價帶入**:`QuoteRefreshNotifier.quoteFor` 優先用本地快取裡 15 分鐘內的報價,
沒有才向 Cloud 補抓。`StockTradeEditorPage` 在這些時機帶入現價:選搜尋結果、
代號停止輸入 0.7 秒、切換交易類型、從持股頁「買進/賣出」進來。只有買進、賣出、
再投入會帶。期初持股填的是成本、現金股利填的是每股股利,所以不帶。使用者自己
改過價格後就不再覆蓋。換了代號才清掉上一檔帶入的價格,從搜尋結果點同一檔時
保留。

## 三端一致

App、Cloud `services/securities/trade_fees.py`、Web
`packages/web-features/src/lib/investment.ts` 是同一套規則,三端測試用同一組跟永豐
對帳單核對過的數字:

- App:`test/services/investment/investment_settings_test.dart`「台股費用對帳」、
  `holding_net_value_test.dart`、`stock_trade_repository_test.dart` 的 0050 買進。
- Cloud:`tests/test_trade_fees.py`。
- Web:`apps/web/src/investmentFees.test.ts`。

**改一邊要改另外兩邊。**

## 實機驗證(2026-09-28,iOS Simulator + 本機 Cloud + Web,證交所真實報價)

- Web 新增交易 → 賣出 → 0050 50 股:自動帶入 112.4,交易稅 5(ETF 0.1%),淨收入
  5,595(手續費取最低 20)。
- App 打開資產頁**之後**,從 Web 買進 0056 50 股(自動帶入 56.65,總成本
  2,832 + 20 = 2,852)。App 沒有切到背景,就自己抓到 0056 的報價,國泰證券市值
  2,702,632 跟 Web 一致。
- App 持股分頁上方的未實現損益 +1,789,417,等於 Web 各檔加總。0050 詳細頁:手續費
  −160、交易稅 −224、淨值 224,416,跟 Web 一樣。
- App 賣出頁:自動帶入 112.4,顯示「證交稅率 0.1%(ETF)」。
- 過程中修掉三個問題:
  - Web 從搜尋結果點同一檔時,帶入的價格被清掉、卻沒有重抓。
  - 持股分頁上方還在用毛市值算損益。
  - 詳細頁「未實現損益(已扣預估賣出費用)」標籤太長,造成溢出。
- 另外,Web 的 service worker 會快取舊版前端,本機測試時要先 unregister 才看得到新版。
