# AI 對話:股票查詢與分析工具

日期:2026-10-03
背景:使用者要求「AI 可以回答有關股票的任何問題,包括交易、設定、賺不賺錢、理財建議」。
FreeChat 維持兩階段(路由 → 唯讀工具 → 回答),本次只擴充工具、prompt 與意圖閘門,
**不改 LLM 往返次數**(仍是 routing 1 次 + answer 1 次,單輪最多 3 個工具並行)。

## 1. 新增 8 個唯讀工具(`lib/services/ai/free_chat_stock_tools.dart`)

共用規則:

- **全部讀本機 SQLite,跨帳本**(同持股頁:`watchAllStockTrades`),不吃 router 的 ledgerId。
- **口徑同持股頁**:持股/市值/未實現損益直接重用 `HoldingView`(含帳戶「損益是否扣預估
  賣出成本」設定);已實現損益重用 `RealizedPnlReport`;其它算法不另寫一份。
- **報價只讀本機快取**,聊天中不打網路。每筆報價回傳 `quote{available, price, quoteTime,
  fetchedAt, session, source, ageHours, stale}`;`fetchedAt` 距今超過 72 小時
  (`kStockQuoteStaleAfter`)標 `stale`;沒報價 `available:false`,該檔不計入市值/未實現。
- **各幣別分開**:所有彙總都是 `byCurrency` / `totalsByCurrency`,絕不跨幣別加總。
- **篩選參數模糊比對**:`account` = 投資理財帳戶名稱(完全相同 > 包含 > 被包含,簡繁摺疊,
  同 `query_transactions.accountName`);`symbol` = 代號(`2330`/`AAPL`/`TW:2330`)或名稱
  (「台積電」),可給陣列;標的名稱來源 = 明細 > 報價 > 定期定額規則。有指定但比對不到時
  回傳 `filters.warning` 與空結果(不會悄悄變成「不篩選」)。
- **大小有上限,彙總永遠涵蓋全部**:持股最多 25 檔、明細樣本預設 20/最多 50、已實現損益
  最多 15 組且每組 5 筆賣出、股利標的最多 15 組,超過標 `truncated`。router 另有
  `maxPayloadChars = 24000` 的最後一道保險。

| 工具 | 參數 | 回答什麼 |
| --- | --- | --- |
| `stock_holdings` | `account`、`symbol`、`includeClosed` | 目前持股:股數/均價/成本/報價資訊/市值/預估賣出費用/淨值/未實現損益(%)/當日漲跌/已實現/股利;`byCurrency` 市值、成本、未實現、`pnlBasis`(`afterEstimatedSellCosts`/`grossMarketValue`/`mixedByAccount`)、未報價檔數、過期報價檔數、最舊報價時間 |
| `stock_trades` | `account`、`symbol`、`startDate`、`endDate`、`tradeType`(buy/sell/opening/cash_dividend/reinvest/stock_dividend/split/dividend)、`limit` | 明細彙總(各幣別買進金額/賣出淨額/**手續費總額/交易稅總額**/筆數,股利匯費與預扣稅另列 `dividendFeeAndTax`)、各類型筆數、`latestTrade`(最近一筆)、日期新到舊的樣本 |
| `stock_realized_pnl` | `year`、`account`、`symbol` | 各幣別已實現損益 + 期間股利 + 賣出勝/負筆數;依標的分組(損益絕對值排序)與賣出明細;`availableYears`。成本一律用全部歷史算(同報表頁) |
| `stock_dividends` | `year`、`startDate`、`endDate`、`account`、`symbol` | 已入帳現金股利/再投入/配股(各幣別)、近 12 個月股利、依標的分組、最近 15 筆;`pendingDividends`(待確認股利,見限制) |
| `stock_settings` | `account` | 各投資帳戶:使用者自訂項目 `customized` 與實際生效值 `effective`(手續費率/折扣/最低/證交稅率(股票/ETF/債券 ETF)/股利匯費/預扣稅/二代健保/預設再投入/損益是否扣賣出成本/預設交割帳戶名稱),生效市場依帳戶設定 > 交易最多的市場 > 幣別 |
| `stock_dca_plans` | `account`、`symbol`、`includeDisabled` | 定期定額規則(`kind='stock_dca'`):標的、每期金額、整數股/碎股、頻率、下次扣款日(`nextPendingOccurrence`)、交割/投資帳戶、手續費覆寫或沿用帳戶、**已執行期數、累計投入、累計手續費、最後執行日** |
| `stock_performance` | `account`、`symbol` | 各幣別 **總報酬 = 未實現 + 已實現 + 股利**、每檔(跨帳戶合併)總報酬排名(>15 檔只列前 8 + 後 7)、**股利殖利率估算**(近 12 個月現金股利+再投入 ÷ 持股成本、÷ 持股市值,只計目前仍持有的標的) |
| `stock_portfolio_analysis` | `account` | 各幣別:集中度(前 8 大標的佔比、單一最大、前三大合計)、帳戶/市場分布、ETF vs 個股(僅台股可分類,其它市場 `unclassified`)、長期虧損標的(持有 ≥365 天且 ≤-10%)、深度虧損(≤-30%)、手續費+交易稅佔累計買進金額、股利概況與殖利率、`observations`(依固定門檻客觀列出的觀察);回傳帶 `disclaimerRequired:true` |

觀察門檻(`kConcentration*`、`kLongLoss*`、`kDeepLossPercent`、`kFeeTaxHighPercentOfBuy`)集中
在檔案開頭常數,會一起回傳在 `thresholds`,方便模型說明「依什麼標準」。

`free_chat_tools.dart` 的改動:`freeChatTools` 末尾展開 `freeChatStockToolSpecs`;
`FreeChatToolExecutor.execute` 多了選填的 `now`、`pendingDividends`,股票工具名稱分派給
`executeFreeChatStockTool`。spec/例外/`formatIsoDate` 抽到 `free_chat_tool_spec.dart`
(`free_chat_tools.dart` re-export,既有 import 不用改),避免兩檔互相 import。
`get_recurring_transactions` 說明補一句「股票定期定額請用 stock_dca_plans」。

## 2. Prompt 規則

**routing**(`free_chat_router.dart::_buildRoutingSystemPrompt`,中英文各一份):

- 「股票相關規則」:問持股/股利/定期定額/賺賠/手續費設定一律用 `stock_*`,**不要用
  `query_transactions`**(買賣股票是轉帳到投資帳戶,不是支出);列出每個問題類型對應的工具;
  symbol/account 依清單填;「今年」→ `year`。
- 「幫我分析/有什麼建議/該不該買賣某檔」→ 呼叫 `stock_portfolio_analysis`,不直接回答買賣建議。
- 「買了/賣了某股票 N 股(張)」是要新增股票交易:**不要用 `record_transaction`**,用
  `type=answer` 說明做法(帳戶頁 → 投資理財帳戶 → 新增股票交易 / 新增轉帳選投資帳戶)。
- 5 個股票範例(賺不賺錢組合工具、今年已實現損益帶入當年、最近一筆、風險分析、買股票說明)。

**answer**(`_buildStockAnswerRules`,只有該輪呼叫過 `stock_*` 工具才附加,省 token):各幣別
分開、不編造(holdingCount/matchedCount 為 0 或 warning 就說沒有)、說明報價時間與過期/缺報價、
說明 `pnlBasis` 口徑、彙總涵蓋全部而 truncated 清單只是一部分、分析類只客觀描述結構與風險且不給
「買/賣某檔」或保證報酬。

**免責聲明(程式保證,不只靠 prompt)**:`FreeChatRouter._withStockDisclaimer` 在下列情況且回答
尚未含「非投資建議/不構成」時,於結尾補上
「以上內容僅供參考,非投資建議,不構成任何買賣推薦。」(英文版同義):呼叫了
`stock_portfolio_analysis`;或使用者問句是投資建議/風險類(`isStockAdviceQuestion`:股票/投資詞
+ 建議/風險詞同時出現,例如「我的股票要不要加碼」),包含 routing 階段直接 `answer` 的情況。

**context**(`free_chat_context.dart`):有投資理財帳戶時多兩行:「投資理財帳戶(股票工具用):…」、
「交易過的股票(持有中的在前):2330 台積電、0050 元大台灣50…」(上限 30 檔,超過加 `…`),
幫模型把使用者講的名稱對上 `symbol`/`account` 參數。沒有投資帳戶時不讀股票明細、不加這兩行。

## 3. 「買了 2330 十股」不再被誤判成支出記帳

`ai_chat_intent.dart` 新增 `isStockTradeIntent`(股票標記:「股」[剔除股東/股份/股市…]、ETF、
零股、shares/stock + 買賣動詞;查詢句先被既有查詢閘門擋掉)與 `isStockAdviceQuestion`。

- `isTransactionIntent`:股票買賣句回 false,不進記帳快路徑。
- `AIChatService.processMessage`:非 `forceChat` 且 `isStockTradeIntent` → **不呼叫 LLM**,直接回
  `stockTradeGuidance`(買賣股票不是支出,說明新增股票交易的入口;中英文)。`forceChat` 時照舊交給
  router,由 routing prompt 規則處理。
- 查詢閘門補了「幾股」(「我買了幾股台積電」是查詢);**刻意不收「張」**(「買了3張電影票」),
  「N 張」的股票買賣由 routing prompt 判斷。
- `AIChatService` 多了選填 `pendingDividends`,`aiChatServiceProvider` 傳入讀取
  `pendingDividendsProvider` 目前快取的 loader。

## 4. 測試

- `test/services/ai/free_chat_stock_tools_test.dart`(44 項):每個工具的有資料/無資料/多幣別
  (TWD+USD)/年度與日期篩選/報價缺失與過期/名稱模糊比對/找不到標的或帳戶/截斷旗標;
  數字都手算過(例:2330 剩餘成本 360,513、淨值 388,275、未實現 27,762;TWD 總報酬 71,023;
  殖利率 0.79% / 0.73%);也涵蓋「帳戶設定關閉扣賣出成本」、待確認股利 loader(有/無/拋例外)、
  定期定額已執行期數、長期/深度虧損、交易成本偏高 observation。
- `test/services/ai/free_chat_router_stock_test.dart`(16 項):工具解析與兩階段、多工具與
  `maxToolsPerTurn`、參數錯誤降級、routing prompt(工具清單/規則/英文版/投資帳戶與標的清單)、
  answer 規則只在用到股票工具時出現、免責聲明(補上/不重複/英文/直接 answer/非建議不補)、
  payload 截斷、pending loader 貫通、`FreeChatContext` 上限。
- `test/services/ai/ai_chat_stock_intent_test.dart`(10 項):意圖閘門正反例、`AIChatService`
  回覆操作說明且不呼叫 LLM/不記帳、`forceChat`、查詢句仍走工具。
- `flutter test test/services test/repositories` 701 項全過;`flutter analyze` 對本次檔案無新增問題
  (`ai_chat_providers.dart` 的 unused `drift` import 是既有警告)。

## 5. 限制 / 沒做

- **待確認股利只能讀 App 目前已載入的快取**(`pendingDividendsProvider`,只在 Cloud 有、不進本機
  DB);沒登入 Cloud 或還沒刷新過就是空/`available:false`,回答會請使用者到投資頁看。
- 報價只讀本機快取,不在聊天中打網路;快取是舊的就如實說明報價時間,不會幫使用者刷新。
- 手續費/稅總額來自明細的 `fee`/`tax` 欄位(含期初持股的手續費 0);舊資料若沒填就是 0。
- 殖利率是估算:持有不到一年或剛買進會低估;只計仍持有標的、不含配股。
- ETF/個股分類只有台股能由代號判斷(`00` 開頭 = ETF),美股等其它市場一律 `unclassified`,
  分析時不會誤報美股 ETF 為個股。
- 沒有做:跨幣別折算成主幣別的「總資產」(使用者要求各幣別分開);歷史某日的市值/未實現
  損益(只有目前快取報價);沒有個股基本面/新聞/預測,也刻意不給買賣建議。
- 「張」的買賣語意交給 routing 模型(同一規則寫在 routing prompt),沒做本地規則,避免誤判
  電影票、演唱會票等。
- `free_chat_stock_tools.dart` 為了與持股頁同口徑,import 了 `securities_providers.dart`
  (`HoldingView`、`holdingTradeOf`);若之後要把 service 層徹底與 provider 層解耦,可以把這兩個
  純邏輯類別搬到 `lib/services/investment/`。
