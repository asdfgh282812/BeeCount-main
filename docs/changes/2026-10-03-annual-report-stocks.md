# 年度記帳報告:加入股票報表 + 更豐富的頁面

日期:2026-10-03

## 入口

- 首頁「年度報告提醒」卡(12/15 ~ 隔年 1/31 出現)→ 年度報告
- 我的 → 年度報告
- 年度報告頁右上角下拉可切年份;底部「分享」按鈕產生長圖海報

## 改了什麼、為什麼

股票功能上線後,年度報告只有一張「投資現金流」補充卡(買賣金額/手續費/股利),看不到
「這一年到底賺賠多少、哪筆最賺」。同時整份報告每個人長得都一樣。這次把報告改成
**依使用者實際資料組頁**:沒有的內容就不出現。

### 純函式(不碰 DB / UI,有單元測試)

- `lib/services/investment/stock_annual_report.dart`:`StockAnnualReport.build(trades, year:, accountCurrency:)`
  - 各幣別分開(不跨幣別加總),依 buy+sell 金額由大到小排序。
  - **已實現損益用全部歷史**(`HoldingsCalculator.realizedEvents`)算成本,再過濾年度賣出事件,
    所以去年買、今年賣的成本會正確延續(跟 `RealizedPnlReport` 同口徑)。
  - 買進金額 = buy 的 amount(含手續費)、賣出金額 = sell 的 amount(淨額),跟
    `InvestmentFlow` 一致;`reinvest` 算股利,不算買進。
  - 年度以交易日期 `yyyy` 判斷(**不**套用帳本的 monthStartDay,見取捨)。
  - `styleTag` 規則見檔頭註解與 `StockAnnualReport.styleOf`(順序即優先序)。
  - `StockAnnualBundle` 另外提供成就判斷(`firstBuyThisYear`、`hasRealizedProfit`、
    `hasHighWinRate`、`isDividendCollector`、`isActiveTrader`)。
- `lib/services/report/annual_persona.dart`:年度稱號規則 `AnnualPersona.decide`
  (股票風格 > 儲蓄率≥30% > 連續記帳≥30 天 > 週末日均≥1.5×平日 > 單一分類≥40% > 入不敷出 > 穩健),
  並產生 2~3 個理由 chip(只取資料真的存在的事實)。

### 資料載入(`annual_report_page.dart`)

`AnnualReportData` 新增:去年收支、支出時段分布(5 桶)、平日/週末支出與天數、`stock`(股票摘要)。
股票摘要在 `annualReportDataProvider` 內以 try/catch 計算,**失敗只記 log、視為沒有股票頁**,
不會讓整份報告失敗。只取目前帳本(`ledgerId`)的 stock_trade,跟既有投資現金流卡同範圍。

### 頁面與觸發條件

| 頁面 | 觸發條件 |
| --- | --- |
| 跟去年比(YoY) | 去年有收支資料 |
| 消費習慣(時段分布 + 平日 vs 週末 + 最長連續記帳) | 年度支出筆數 ≥ 5 |
| 股票年度總覽 | 該年度有股票 buy / sell / 股利 |
| 股票亮點(投資風格、最賺/最賠、勝率環、領息王、最常交易、每月已實現損益) | 同上(內部各區塊再依資料決定顯示) |
| 年度稱號 | 年度記帳 ≥ 10 筆 |
| 成就牆 | 原本 3 個;**有股票交易時**多 5 個股票成就(首次買股、獲利入袋、勝率≥60%且賣出≥5、領息≥3 筆、買賣≥40 筆) |

頁面順序:總覽、洞察、收支對比、分類、月度趨勢、(YoY)、(習慣)、特別時刻、(股票×2)、(稱號)、成就。
新頁面在 `annual_report_extra_pages.dart`,文字/圖示對照在 `annual_report_labels.dart`(頁面與海報共用)。

### 與既有「投資現金流」卡整合

第一頁那張卡保留(它回答「淨儲蓄為什麼不等於剩下的現金」:買股票的錢是轉帳、不計收支),
但**年度有股票頁時只留「淨投入未計入收支」那段與缺匯率警示**,手續費/股利/買賣明細改在股票頁
(依證券幣別)看,避免重複;只有股利、沒有買賣時這張卡整張隱藏。

### 股票漲跌色

沿用 `stockUpIsRedProvider`(外觀設定「股票漲跌顏色」,與收支配色獨立),顏色規則同
`investment_ui.dart::pnlColor`。海報也吃這個設定。

### 海報

`AnnualReportPoster` 新增 `stockUpIsRed` 參數與 `_buildStockSection`:有股票資料時(活躍度最高的幣別)
顯示已實現損益 / 股利 / 勝率(沒有勝負資料時顯示交易筆數)+ 投資風格;沒有股票資料時完全不畫,海報不變。
「隱藏收入」開關會一併遮罩損益與股利。

### l10n

新增 99 個 key(`annualStock*`、`annualPersona*`、`annualYoY*`、`annualHabits*`)到
`app_en` / `app_zh` / `app_zh_TW` / `app_ko`(ko 為意譯,待社群校對)。

## 取捨 / 刻意不做

- **年度口徑**:股票以交易日期 `yyyy` 算(同 `RealizedPnlReport`),不套帳本 `monthStartDay`;
  monthStartDay ≠ 1 的帳本,第一頁現金流卡(用帳本年度區間)與股票頁的年度邊界可能差幾天。
- **多幣別不加總**:股票頁用 chip 切換幣別;稱號與海報取活躍度最高的幣別。
- **styleTag 優先序**:activeTrader → dividendHunter → longTermHolder → beginner(買+賣 < 5)→ swingTrader,
  與 Cloud `services/securities/annual.py::_style_tag` 完全同序,兩端稱號一致。
- 去年比較只比收入/支出/淨儲蓄(`yearlyTotals`),沒有逐分類比較;標籤頁(Web 有)未移植。
- 年度收支都為 0(只有股票轉帳)時,`annualReportDataProvider` 仍回 null(沿用既有「無資料」),不會出股票頁。
- 沒有針對整頁(含 provider)的 widget 測試;新頁面有煙霧測試(多幣別切換、窄螢幕不 overflow)。

## 測試

- `test/services/investment/stock_annual_report_test.dart`(跨年成本、勝率、月分桶、多幣別排序、各 styleTag、成就判斷)
- `test/services/report/annual_persona_test.dart`
- `test/pages/report/annual_report_extra_pages_test.dart`
