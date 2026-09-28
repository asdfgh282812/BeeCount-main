# 股票持股(Stock Holdings)— Phase 1

日期:2026-09-28
跨 repo:本 repo(App)+ BeeCount Cloud(`/Users/andy/BeeCount-Cloud`,server + Web)。
Cloud 端設計文件:`BeeCount-Cloud/docs/STOCK_HOLDINGS_SD.md`。

## 背景與使用者確認的決策

使用者要的是:買股票就是一筆「轉帳」,同時記下**股數**(不是金額),市值用
「股數 × 現價」算;股票**不算淨資產**(不是馬上能花的錢),另外顯示成預估
市值;支援股利、股利再投入;手續費/交易稅/股利手續費/預扣稅全部**使用者
自訂**,不寫死。

討論後確認:

- **沿用既有「投資理財」(`investment`)帳戶類型**,不新增帳戶類型(使用者
  明確否決了新增 `securities` 類型的提案)。
- **Cloud Web 跟 App 功能對等**(買、賣、看持股/市值、費用設定),Cloud 另外
  負責它專屬的工作(抓證券清單/報價/除權息資料、排程)。
- 報價/股利資料來源:**免費來源 + Provider 抽象**(台股:證交所/櫃買官方
  OpenAPI;美股與其它市場:Yahoo Finance 非官方端點)。只有 Cloud 能抓。
- 報價更新時機:**收盤後抓收盤價 + 打開 App/Web 時盤中快取超過 15 分鐘就
  補抓**。
- 股利:Server 偵測 → 待確認通知 → 使用者確認實收金額或選再投入才入帳
  (**Phase 2,這次沒做**,見文末)。

## 使用者入口

- **帳戶頁 → 淨資產卡下方「投資市值(預估)」卡**:所有投資理財帳戶持股市值,
  折算成主幣別;點進去是「投資總覽」(依帳戶列出持股)。沒有任何持股時這張卡
  不顯示。
- **帳戶頁 → 點「投資理財」帳戶 → 「持股」分頁(第一個分頁)**:持股清單、
  市值/成本/未實現損益、更新報價、「新增股票交易」、「費用設定」。點一檔持股
  → 持股詳情(交易紀錄、加碼/賣出、手動輸入價格)。
- **帳戶頁 → 投資理財帳戶 → 「帳戶資訊」分頁 → 費用設定**:同上的費用設定頁。
- 一般交易列表裡由股票交易產生的轉帳,點編輯會直接導到「編輯股票交易」頁
  (見下方「轉帳不能單獨改」)。
- Web:頭像下拉選單 →「投資」;或資產頁的「投資市值(預估)」卡。

## 1. 資料模型(schema v62 → v63,`lib/data/db.dart`)

- **`StockTrades` 表(新,ledger-scoped,同 `Debts`)**:`syncId`/`ledgerId`/
  `accountId`(投資理財帳戶本地 id)/`market`/`symbol`/`securityName`/
  `tradeType`/`shares`/`price`/`fee`/`tax`/`amount`/`currency`/`tradeDate`/
  `txSyncId`/`dividendEventRef`/`note`。
  - `tradeType`:`buy`/`sell`/`opening`(期初持股,沒有金流)/
    `stock_dividend`(配股)/`cash_dividend`/`reinvest`(後兩個是 Phase 2)。
  - `shares` 用 REAL,支援美股零碎股。
  - `amount` = 以證券幣別計的現金影響:buy/opening = 股數×價格+手續費,
    sell = 股數×價格−手續費−稅。
  - `txSyncId` 指回綁定的轉帳交易 syncId(syncId 對 syncId 的純文字連結,同
    `Debts.originTransactionSyncId`,不解析成本地 id)。
- **`SecurityQuotes` 表(新,不同步,同 `ExchangeRates`)**:本地報價快取,
  key `(market, symbol)`;`session` = `close`/`intraday`/`manual`。
- **`Accounts.investmentSettingsJson`(新欄位)**:投資理財帳戶的費用設定 JSON,
  解析見 `lib/models/investment_settings.dart`。
- migration 用既有的 `_addColumnIfMissing`/`_createTableIfMissing`,另外建
  `idx_stock_trades_account` 索引(`onCreate` 也補建,理由同 v48/v49)。

**持股不落庫**:股數/平均成本/已實現損益由 `StockTrades` 即時算
(`lib/services/investment/holdings_calculator.dart`,移動平均成本法,台灣
券商慣例)。理由同 `Debts` 不存 `remainingAmount`:避免 App push / Web write
兩條路徑各自維護一份衍生值而漂移。Cloud 端 `src/services/securities/holdings.py`
是同一套算法,**兩邊共用 `test/fixtures/stock_holdings_vectors.json` 測試向量**
(Cloud 那份在 `tests/fixtures/`,內容必須一模一樣;App 的測試在兩個 repo
並排時會直接比對兩份檔案)。改算法要兩邊一起改、一起更新向量。

## 2. 買賣 = 轉帳(`lib/services/investment/stock_trade_tx_mapper.dart`)

| 動作 | 轉帳 | 金額欄位 |
|---|---|---|
| 同幣別買進 | 交割帳戶 → 投資理財帳戶 | `amount` = 股數×價格,`feeAmount` = 手續費 |
| 同幣別賣出 | 投資理財帳戶 → 交割帳戶 | `amount` = 股數×價格,`discountAmount` = 手續費+交易稅 |
| 跨幣別買進(台幣交割戶買美股) | 同上 | `amount` = 交割金額(使用者填,已含費用),`toAmount` = 股數×價格+手續費 |
| 跨幣別賣出 | 同上 | `amount` = 股數×價格−費−稅,`toAmount` = 交割金額 |

跟 Cloud `snapshot_mutator.stock_trade_tx_fields` 是同一套規則(Web 買賣走
那邊),改一邊要改另一邊。跨幣別時如果轉入帳戶幣別剛好是帳本本位幣,
`nativeAmount` 直接用 `toAmount`(精確值,同 `transfer_form.dart` 2026-09-18
的修正),其它情況交給 `_resolveTxCurrency` 兜底。

**原子寫入**:`LocalRepository.createStockTrade`/`updateStockTrade`/
`deleteStockTrade` 在同一個 `db.transaction` 裡一起處理明細與轉帳,各自記
`stock_trade` 與 `transaction` 的 change。`deleteTransaction` 反過來會連帶
刪掉 `txSyncId` 指向它的明細(同 Cloud `_cascade_delete_linked_stock_trades`),
`deleteLedger` 也會一起清掉該帳本的明細。

**轉帳不能單獨改**:`TransactionEditUtils.editTransaction` 碰到有綁股票明細
的轉帳,直接導到 `StockTradeEditorPage`——在一般轉帳表單改金額/帳戶的話
股數不會跟著變,持股就對不上。

**賣超**:`createStockTrade`/`updateStockTrade` 會檢查持有股數(跨所有帳本,
帳戶是 user-global),UI 也先擋一次。

## 3. 同步

- `stock_trade` 是 **ledger-scoped**(`recordLedgerChange`,**不是**
  user-global)。
- `entity_serializer.dart::serializeStockTrade` 的 key 對齊 Cloud
  `sync_applier.py::_LEDGER_MERGE_SPECS["stock_trade"]`,
  `test/sync/stock_trade_apply_test.dart` 有一條測試直接比對 key 集合。
- account 多了 `investmentSettings`(物件):本地欄位 null 時不帶 key(server
  缺鍵保留),設定過之後恆發;apply 端 containsKey 保護。
- `fullPush` 也會推明細。
- 舊版 App pull 到不認識的 `stock_trade` 只會記 warning 並略過
  (`sync_engine_apply.dart` 的 default case),不會壞。

## 4. 報價(`lib/providers/securities_providers.dart`)

- `QuoteRefreshNotifier.refresh()`:拉持有標的的報價
  (`BeeCountCloudProvider.fetchSecurityQuotes`),寫進 `SecurityQuotes`。
  觸發點:帳戶頁 initState、App 回到前景(`app.dart` resumed)、持股頁
  開啟/下拉。1 分鐘內不重打(真正的 15 分鐘盤中快取判斷在 server)。
- 非 Cloud 使用者:可以在持股詳情「手動輸入價格」(`session='manual'`)。實務
  上目前所有使用者都要登入 Cloud(授權金鑰機制),這是保底。
- `investmentAccountMarketValuesProvider`:有持股的投資理財帳戶在帳戶列表以
  **市值**(帳戶幣別)取代交易累計的成本餘額;任何一檔缺報價/缺匯率就退回
  原本的餘額,不顯示少算的市值。只影響帳戶列與分組小計,不影響淨資產卡。

## 5. 淨資產分離

- 新建投資理財帳戶預設 `includeInTotal = false`
  (`account_edit_page.dart::_selectType`,Web 的 `AccountsPanel` 同步做了)。
  既有帳戶不動。
- 在「仍計入淨資產」的既有投資理財帳戶第一次記股票時,會跳一次提示建議排除
  (`StockTradeEditorPage._suggestExcludeFromTotal`)。
- 淨資產計算本身沒改——靠既有的 `includeInTotal` 過濾。

## 6. 費用設定(`lib/models/investment_settings.dart`)

欄位全部選填,null = 沿用市場預設(`InvestmentSettings.defaultsFor`,台股:
0.1425%、折扣 1、最低 20、證交稅 0.3%、股利匯費 10、二代健保 2.11%/門檻
20,000;美股:0.25%、預扣稅 30%)。建議手續費 = max(成交金額×費率×折扣,
最低),TWD/JPY/KRW 無條件捨去到整數、其它四捨五入到分——跟 Web 的
`web-features/src/lib/investment.ts` 同規則。每筆交易都能覆寫;使用者改過
手續費/稅欄位後就不再自動覆蓋。

交割帳戶預帶順序:費用設定裡指定的 → 這個帳戶上一筆買賣用的交割帳戶。

## 7. 實機驗證(2026-09-28,iOS Simulator + 本機 Cloud)

用 Web API 建帳本/帳戶/4 筆交易(台股兩檔買進、2330 賣出 200 股、複委託
跨幣別買 AAPL),App pull 後:淨資產 = 交割戶實際餘額(不含股票)、投資市值卡
= server `/workspace/holdings` 的總額、持股頁平均成本/已實現損益都對。過程中
抓到兩個 bug 已修:

- `formatPrice` 用了 `replaceFirst(..., r'$1')`——**Dart 不支援 `$1` 群組
  引用**,整數價格直接 RangeError。已改寫並加測試
  (`test/services/investment/investment_ui_format_test.dart`)。
- 今日漲跌算錯:Cloud 打 Yahoo chart 用 `range=5d`,`chartPreviousClose` 是
  5 天前的收盤價。Cloud 已改 `range=1d` 並加測試。

## 沒做、刻意延後(Phase 2 / 3)

- **股利**(Phase 2):除權息事件同步、待確認股利偵測與通知、Server 端確認
  入帳、股利再投入。`cash_dividend`/`reinvest` 類型、`dividendEventRef` 欄位、
  費用設定裡的股利相關欄位已經先放進資料模型,UI 目前不能手動建這兩種類型。
- 股票分割、已實現損益報表、AI 對話查詢持股、管理後台切換付費資料來源
  (Phase 3)。
- Web 建立交易時轉帳備註是 server 的中文預設格式(「買進 2330 台積電
  1000股」),App 建立的才是在地化文字。
