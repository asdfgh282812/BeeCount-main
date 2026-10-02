# 股票持股 Phase 3:股票分割、已實現損益報表(App 端)

日期:2026-10-02
Cloud 端對應:`BeeCount-Cloud/docs/STOCK_HOLDINGS_SD.md`(Phase 3,Web 功能對等)。

## 1. 股票分割(`split`)

- 新 `trade_type = 'split'`(wire 與 DB 同字串),**沒有新表/欄位、不需 DB migration**
  (沿用 schema v64)。`shares` 欄位存「分割比例」= 每 1 股變成幾股(1 拆 4 → 4;
  2 合 1 反向分割 → 0.5);`price` 為 null、`fee/tax/amount` 皆 0、`tx_sync_id` 為 null,
  不建任何轉帳/income 交易(只建明細,同 `stock_dividend`)。
- `holdings_calculator.dart`:`split` → 股數 *= 比例、總成本不變(平均成本自動 / 比例)。
  同日排序改為 opening, buy, reinvest, stock_dividend, **split**, cash_dividend, sell。
  比例 <= 0 視為無效、忽略(不會把持股歸零)。
- 同步:push/pull 的 stock_trade wire 本來就有這些欄位,`split` 只是新的 tradeType 值,
  pull 套用(`sync_engine_apply`)與 push 序列化(`entity_serializer`)沒有類型白名單,不需改。
  `kStockTradeTypes` 加入 `split`,`createStockTrade` 的類型檢查因此放行。
- 編輯頁(`StockTradeEditorPage`):新增「股票分割」選項,輸入「1 股變成幾股」(例 4,
  反向分割 0.5,附說明文字),不顯示價格/手續費/交割帳戶/金額,存檔不建轉帳;
  `LocalRepository.createStockTrade/updateStockTrade` 對 split 強制 fee/tax = 0、price = null。
- 持股詳情頁明細列顯示「分割 1→4」。
- 賣超檢查只針對 sell;`stock_trade_tx_mapper` 沒改(split 不會走到它,
  `stockTradeAmount` 對 split 回 0)。

## 2. 已實現損益

- `HoldingsCalculator.compute(..., realized: list)` / `HoldingsCalculator.realizedEvents(trades)`:
  每筆 sell 輸出一筆 `RealizedPnlEvent`:`tradeSyncId, accountKey(wire accountId), market,
  symbol, securityName, currency, date(yyyy-MM-dd), shares(實際賣出股數,賣超時只算持有部分),
  proceeds(該筆 sell amount,淨收入), costBasis(賣出當下平均成本 × 賣出股數), pnl`。
  `toWire()` 為 camelCase 同名。
- 新頁面「已實現損益」(`pages/investment/realized_pnl_page.dart`),入口:帳戶頁
  「投資市值」卡 → 投資總覽頁,第一張卡下方的「已實現損益」列。
  - 篩選:年度(含全部)/帳戶/標的。
  - 頂部各幣別分開彙總已實現損益 + 累計股利(cash_dividend + reinvest 的 amount,
    口徑同持股頁),不跨幣別加總。
  - 下方依標的分組,可展開看每筆賣出(日期、股數、賣出收入、成本、損益);損益顏色用
    既有 `pnlColor`(沿用收支配色,紅漲綠跌設定)。
  - 計算邏輯在純函式 `services/investment/realized_pnl_report.dart`;成本一律用全部明細
    算,所以篩年度不會改變單筆賣出的成本。資料全部來自本機 Drift(`stockTradesProvider`),
    不呼叫 Cloud API。
- i18n:新增 key 加在 `app_en.arb`、`app_zh_TW.arb` 並以 `flutter gen-l10n` 重新產生
  (`lib/l10n/app_localizations*.dart` 有進版控)。`app_zh.arb`/`app_ko.arb` 本來就沒有任何
  `stock*` key(股票功能全部走英文 fallback),這次維持一致沒有補。

## 3. 測試

- 共用向量 `test/fixtures/stock_holdings_vectors.json` 新增 4 個案例:
  `split_4_for_1_then_sell`(含 `realizedEvents`)、`split_4_for_1_only_avg_cost_divides`、
  `reverse_split_2_for_1`、`same_day_order_stock_dividend_split_cash_dividend_sell`。
  向量可選的 `realizedEvents` 區塊由 `holdings_calculator_test.dart` 驗證。
- `holdings_calculator_test.dart` 補 realizedEvents(賣超、損益加總等於 realizedPnl)與
  比例 <= 0 的測試;新增 `realized_pnl_report_test.dart`(各幣別彙總、年度/標的/帳戶篩選)。
- 注意:「向量檔與 Cloud 副本相同」那個測試在 Cloud repo 還沒同步同一份向量前會失敗
  (預期行為,兩邊檔案內容必須逐字相同)。
