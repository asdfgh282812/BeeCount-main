# 股票持股 Phase 2 — 股利

日期:2026-09-28
接續 `docs/changes/2026-09-28-stock-holdings.md`(Phase 1)。跨 repo:本 repo(App)+
BeeCount Cloud(`/Users/andy/BeeCount-Cloud`,server + Web)。Cloud 端設計見
`BeeCount-Cloud/docs/STOCK_HOLDINGS_SD.md` §7。

## 使用者確認過的決策(Phase 1 規劃時)

- 除權息資料由 **Server** 從網路抓、存在 server DB。
- Server 偵測到股利 → **待確認通知**,使用者確認實收金額或選擇再投入後才入帳。
- 確認入帳**統一由 Server 建交易**(App 跟 Web 行為一致;App 確認後 sync pull 拿回)。
- 股利手續費(匯費)、預扣稅、二代健保全部**使用者自訂**(Phase 1 的費用設定裡早就有欄位)。

## 使用者入口

- **資產頁 → 「投資市值(預估)」卡 → 「N 筆股利待確認」**(展開時的一行;卡片折疊
  時圖示右上角有個提示點)→ 待確認股利頁 → 「確認入帳」/「忽略」。
- **資產頁 → 投資理財帳戶 → 「持股」分頁最上方**:同一個入口,只算這個帳戶的。
- **通知中心**:category=`dividend` 的通知(「股利待確認:2330 台積電」),點了直接
  開待確認股利頁(`notification_center_page.dart::resolveNotificationJumpTarget`,
  `pendingDividendId` 優先於 `accountId`)。
- **手動補記股利**:持股分頁 →「新增股票交易」→ 類型選「現金股利」或「股利再投入」
  (資料源漏抓、或自己想記的時候)。
- Web:頭像選單 →「投資」→「待確認股利」區塊;資產頁投資市值卡有「N 筆股利待確認」。

## 1. 交易怎麼記

| 類型 | 產生的交易 | stock_trade 欄位 |
|---|---|---|
| `cash_dividend` 現金股利 | `income` → 入帳帳戶(任何非群組帳戶,可以是投資帳戶本身),分類「股利」 | shares=持有股數、price=每股股利、fee=股利手續費、tax=預扣稅+二代健保、amount=實收 |
| `reinvest` 股利再投入 | `income` → 這個投資理財帳戶本身,分類「股利」 | shares=買進股數、price=買進價、fee、amount=成本 |
| `stock_dividend` 配股 | 無(Phase 1 就有) | shares=配股數 |

- **分類「股利」**:App(`LocalRepository._ensureDividendCategory`)跟 Cloud
  (`card_rewards.ensure_dividend_category`)都用「同名 income 分類」找/建,名字寫死
  中文「股利」,所以兩邊不會各建一個。代價是英文介面也叫「股利」(跟 Cloud 既有的
  「回饋金」「退款」同一個慣例)。
- 再投入的收入進投資帳戶本身:投資帳戶的「餘額」在 Phase 1 就是成本累計,再投入等於
  用股利加碼,成本跟著增加,帳就平了。
- 收入金額四捨五入到分(零碎股再投入 0.0055 股 × 341.07 = 1.875885 → 1.88);
  stock_trade.amount 保留原精度給持股成本用。
- 入帳帳戶幣別跟證券幣別不同(例:美股股利入台幣帳戶)時要填「實際入帳金額」,
  規則同 Phase 1 的跨幣別買賣(`stock_trade_tx_mapper.dart::stockDividendTxAmount`)。
- 持股計算不用改:`holdings_calculator.dart` 在 Phase 1 就已經處理 `cash_dividend`
  (只加累計股利)跟 `reinvest`(加股數、成本、累計股利)。

## 2. 實收估算(`lib/services/investment/dividend_estimate.dart`)

總額 = 股數 × 每股股利(TWD/JPY/KRW 捨去到整數);預扣稅 = 總額 × 預扣稅率;二代健保 =
總額 ≥ 門檻時 × 費率;手續費 = 固定 + 總額 × 費率;實收 = 總額 − 以上。配股 = 股數 ×
配股率(台股先四捨五入到千分位再捨去——證交所的配股率是截斷過的 0.04999999,直接
捨去 1000 股會變 49 股)。

**Cloud `dividends.estimate_dividend`、Web `estimateDividend` 是同一套規則,三端
測試用同一組數字**(`test/services/investment/dividend_estimate_test.dart`、Cloud
`tests/test_stock_dividends.py`、Web `investmentDividend.test.ts`)。改一邊要改三邊。

## 3. 待確認股利(App 不存本地)

- `lib/providers/securities_providers.dart`:`PendingDividend`(server JSON 模型)、
  `pendingDividendsProvider`(StateNotifier;1 分鐘節流)、`accountPendingDividendsProvider`。
  **狀態只在 server**,不進 Drift、不走 sync——確認後 server 建的明細/交易靠 sync pull
  回來(`confirm()` 會主動觸發一次 `SyncEngine.sync`,WS 也會通知)。
- 刷新時機:資產頁 initState、App 回到前景(`app.dart`)、持股分頁開啟/下拉、待確認頁。
- `BeeCountCloudProvider`:`fetchPendingDividends` / `confirmPendingDividend` /
  `setPendingDividendDismissed` / `fetchDividendEvents`。
- UI:`lib/pages/investment/pending_dividends_page.dart`(`PendingDividendsBanner`、
  `PendingDividendsPage`、`ConfirmDividendPage`)。確認頁預帶:入帳帳戶 = 費用設定的
  交割帳戶 → 這個帳戶最近一筆買賣的交割帳戶(server 算好給);再投入價格 = 快取報價;
  再投入股數 = 實收 ÷ 價格(台股捨去到整股、其它 6 位小數)。

## 4. 交易日期存當地中午

`StockTradeEditorPage` 的交易日期(預設今天、日期選擇器)改存**當地中午**,跟 Web
`dateValueToIso` 同一個做法。原因:server 判斷「除息日前一天有沒有持股」時會把交易
日期換成**市場當地日期**比;存午夜的話,換成紐約時間會變前一天。舊資料不動。

## 5. 其它

- `stockDeleteTradeConfirm` 文案從「轉帳也會一起刪除」改成「轉帳或股利收入」。
- What's New 3.7.0 多一則 `whatsNew370StockDividends*`。
- `stock_trade` 的 wire 格式沒變(Phase 1 就有 `dividendEventRef`、`cash_dividend`/`reinvest`
  類型);server 確認時會填 `dividendEventRef = "TW:2330:2026-09-16"`,App 只是照存。

## 實機驗證(2026-09-28,iOS Simulator + 本機 Cloud + Web)

真的連到證交所/Yahoo 跑 `security_dividend_sync`(抓到 2330 9/16 每股 7 元、AAPL 8/10
0.27 美元等 5 筆事件)→ `security_dividend_detector` 建 2 筆待確認 + 通知:

- Web 確認 2330 現金入帳 → 交割戶 +6,990(7,000 − 匯費 10);App pull 後餘額、月曆
  +7.0k、累計股利都對。
- App 確認 AAPL 再投入(0.0055 股 @ 341.07)→ server 建 reinvest 明細 + 美元 income
  (自動補台幣折算);App pull 後持股 10.0055 股。
- Web 刪掉那筆再投入 → 排程把 AAPL 退回待確認(不重發通知)→ App 刷新看得到;
  App 忽略 / 放回待確認都正常。

## 沒做、刻意延後

- 發放日(pay date):證交所預告表跟 Yahoo 都沒有,欄位先留著(一律 null),確認時
  預設入帳日期用除息日。要補得接公開資訊觀測站。
- 部分再投入(一部分現金、一部分買股):不支援,只能二選一。
- 預扣稅在「再投入」模式不另外記(reinvest 明細沒有欄位放,備註可以自己寫)。
- 股票分割、已實現損益報表、AI 查詢持股(Phase 3)。
