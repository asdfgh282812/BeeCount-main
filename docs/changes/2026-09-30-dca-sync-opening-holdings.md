# 定期定額 App↔Web 顯示、代號自動帶入名稱、批次期初持股(App 端)

接續 `2026-09-30-stock-dca-whole-shares.md`。Cloud/Web 端見 BeeCount Cloud repo
`docs/STOCK_HOLDINGS_SD.md` §10.3。

## 使用者回報 → 根因

| 回報 | 根因 / 處理 |
| --- | --- |
| Web 建的定期定額在 App「週期記帳」顯示成 `transfer · 3000.00`、「股票定期定額」篩選是空的;App 建的在 Web 也是轉帳 | 使用者跑的 App 是從 `release/3.7.0` build 的(`BeeCount-main` 的 Xcode workspace),`2026-09-29-stock-dca-fixes.md` 的六個同步欄位修正還在 `fix/stock-dca` 分支沒合進去。合併後,舊版 App 建的規則要在 App 打開按一次儲存才會重推 `kind` 等欄位 |
| App 列表標題顯示原始字串 `transfer` | `recurring_rule_list_page.dart` 沒備註/商家時直接用 `rule.type` 當標題。改成顯示「轉帳/收入/支出」 |
| Web 規則顯示「每月 ×30」、App 顯示「每30月」 | 使用者把「每月 30 號」填進間隔。資料沒錯,Web 表單的間隔欄語意改清楚(見 Cloud 文件);App 的定期定額頁本來就是「每月 N 號」選法,不受影響 |
| 定期定額輸入 0056、離開輸入框後名稱沒帶入 | 定期定額頁的代號欄沒有任何查詢;股票交易頁有(debounce 0.7 秒查報價),但只在「買進/賣出/再投入」才帶名稱,「期初持股/股利」不帶 |
| 期初持股希望能快速輸入/匯入 | 見下方「批次期初持股」 |

## 代號自動帶入名稱

- `recurring_stock_rule_editor_page.dart`:代號欄停頓 0.7 秒或離開輸入框就呼叫
  `QuoteRefreshNotifier.quoteFor`,精準命中時帶入名稱(報價也寫進快取,金額下方
  的整數股試算會跟著出現);換市場後重查。名稱只在空白或還是上一次自動帶入的值時
  才覆蓋(`_autoName`),手打的名稱不動;查不到代號時清掉上一檔自動帶入的名稱。
- `stock_trade_editor_page.dart::_prefillPrice`:名稱帶入不再限定買賣類型(期初持股
  /股利也帶),價格仍只有買進/賣出/再投入才帶現價;加上離開輸入框立即查詢。

## 批次期初持股

建議(也是實作的方向):開始記帳前就持有的股票**一檔一筆、填平均成本**,不要逐筆
補記過去的每次買進。持股計算本來就是加權平均,股數 + 總成本對了,持股成本、未實現
損益就完全一樣;少掉的只有記帳前個別買進的日期與已實現損益,對記帳用途不重要。券商
App 的「庫存」頁就有股數跟成本均價,照抄最快。

- `lib/services/investment/opening_holdings_import.dart`(純函式,Web
  `lib/investment.ts` 同名函式、同一組測試字串):
  - `parseOpeningHoldingsText`:一行一檔「代號 股數 成本」,可夾名稱。有 tab 用
    tab 切(Excel/Google 試算表複製);空白切得出 3 欄以上用空白(逗號當千分位);
    否則當 CSV。第一個英數字欄位是代號,之後前兩個數字依序是股數、成本,其它非數字
    欄位當名稱。解析不出來的行(標題列等)算 `skipped`。
  - `openingTradeFromCost`:平均成本模式 → 價格 = 均價、手續費 0;總成本模式 →
    價格 = 總成本 ÷ 股數(4 位小數),台幣價金捨去的零頭放手續費,存下來的成本剛好
    等於輸入。
- `lib/pages/investment/opening_holdings_batch_page.dart`:市場、持股日期、成本模式
  (平均成本/總成本)、多列輸入(代號/名稱/股數/成本,每列顯示總成本;已持有同代號
  時提示「會再加上去」)、「從剪貼簿貼上」。貼上後一次 `refresh(extraKeys:)` 抓完
  報價再帶名稱——`refresh` 正在跑時會直接略過,所以不能每列各自 `quoteFor`。儲存時
  每列呼叫既有的 `createStockTrade(tradeType: opening)`,沒有新的資料結構或同步欄位;
  中途失敗時已存的列從清單移除,避免重按又存一次。第一次在這個帳戶記股票時一樣會
  問要不要排除淨資產(同股票交易頁)。
- 單筆期初持股(`stock_trade_editor_page.dart`):價格欄改叫「平均成本」,不再依
  帳戶費率自動估手續費(券商成本均價通常已含手續費),提示文字說明一檔一筆就好。

## 入口

- 帳戶 → 投資理財帳戶 → 新增交易 → 選「期初持股」→ 提示下方「一次新增多檔期初持股」。
- 帳戶 → 投資理財帳戶 → 持股頁還沒有任何持股時,「新增交易」下方的
  「一次新增多檔期初持股」。
- Web:投資頁帳戶卡「期初持股」按鈕,或股票交易 dialog 選「期初持股」後的連結。

## 刻意沒做

- 券商對帳單/交易明細 CSV 匯入:各家格式不同,還牽涉配股/減資,之後要做可以在
  parser 前面加券商格式轉換。
- 貼上時同代號多行不合併:各存一筆,持股計算結果相同。
- 名稱在代號前面且名稱本身是英數字(例如 `Apple AAPL 10 150`)會把名稱當代號;
  提示文字寫的格式是代號在前。

## 測試

- `test/services/investment/opening_holdings_import_test.dart`:tab/空白/CSV、千分位、
  名稱在前、單位/貨幣符號、略過標題列與不完整的行、平均/總成本換算(含台幣零頭)。
  Web `investmentFees.test.ts`「期初持股匯入」同一組。
