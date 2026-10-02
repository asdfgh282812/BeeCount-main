# 股票定期定額修正與重新驗證(App 端)

接續 `2026-09-28-stock-dca-recurring.md`。使用者回報四件事,都跟原本「App 與
Cloud 各自實作、沒接同步欄位」有關,另外把整個功能(UI/操作/生成邏輯)重新
審查了一遍。Cloud/Web 端的對應修正見 BeeCount Cloud repo
`docs/STOCK_HOLDINGS_SD.md` §10.1。

## 使用者回報的問題 → 根因

| 回報 | 根因 |
| --- | --- |
| App 建的定期定額,Web 週期性交易頁的圖示不對(顯示轉帳) | `EntitySerializer.serializeRecurringRule` 沒推 `kind/market/symbol/securityName/stockFeeRate/stockFeeMin`,Cloud 收到的是普通 transfer 規則 |
| 「下次執行時間」設 11:45,11:50 執行排程後沒生成交易 | (1) 同上,Cloud 的定期定額排程根本找不到這條規則;(2) Cloud 只讀報價快取,而收盤報價排程只抓「已持有」標的,第一期還沒買的代號永遠沒報價;(3) Cloud 餘額公式把預生成的未來支出也扣掉 |
| Web 新增規則輸入代號不會出現股票、「新增規則」按不下去 | Web 端問題,見 Cloud 文件 |
| 希望在股票交易裡就能新增定期定額 | App 只有持股頁有一顆「定期定額」按鈕,股票交易頁沒有入口,也看不到既有計畫 |

## 同步(`lib/cloud/sync/`)

- `entity_serializer.dart::serializeRecurringRule`:恆發上面六個欄位(含
  null)。Cloud merge spec 是「key 有出現就覆蓋」,null 要照發,清除手續費覆寫
  才同步得出去。
- `sync_engine_apply.dart::_applyRecurringRuleChange`:解析同六個欄位,用
  `containsKey` 保護——舊版 Cloud(migration 0060 之前)payload 沒這些鍵時不
  沖掉本地值;新規則缺 `kind` 時落 `'general'`(Cloud 快照對一般規則不寫 kind)。
- 沒做自動補推:3.7.0 之前建的 App 端定期定額規則在 Cloud 上仍是
  `kind='general'`,要在 App 打開規則按一次儲存(或刪掉重建)才會重推。刻意
  不做「啟動時全部重推」,避免重蹈 2026-09-29 backfill 用本機舊資料覆蓋雲端的
  事故。

## 生成邏輯(`LocalRepository`)

- `materializeDueTransferRules` 排除 `kind='stock_dca'`。以前自動扣繳排程先跑,
  會把定期定額當普通轉帳生成一筆沒有持股明細的轉帳、並把進度推過去,股票排程
  永遠輪不到。
- `materializeDueStockRules` 改成逐條呼叫 `_materializeStockRule`,每條包
  try/catch:一條規則壞掉(例如交割戶幣別跟證券不同 → `createStockTrade` 丟
  `StockTradeSettlementAmountRequired`)以前會讓例外一路丟到
  `appSplashInitProvider`,連前面已寫入的自動扣繳後處理(UI 刷新/同步/通知)都
  跳過,且每次啟動重演。現在回報成 `RecurringRuleStockSkipReason.failed`。
- **固定 syncId**(`lib/services/investment/stock_dca.dart::stockDcaOccurrenceIds`):
  每一期的 StockTrade/轉帳 syncId = uuid5(規則 syncId + 該期秒級 epoch),跟
  Cloud `stock_dca_occurrence_ids` 同算法(雙邊測試對照同一組固定值)。App 是
  「啟動先生成、之後才 pull」,Cloud 是 15 分鐘排程,兩邊生成同一期時只會
  互相覆蓋(LWW),不會變兩筆。本地已有同 syncId 的明細(pull 下來的)就只推進
  進度。`createStockTrade` 新增 `syncId`/`txSyncId` 參數,只給這裡用。
- **補期上限 7 天**(`kStockDcaMaxCatchUp`,Cloud 同值):到期只讀得到當下報價,
  起始日設在很久以前 / 停用後重啟 / 很久沒開 App 時,超過 7 天的期數略過不買
  (`staleSkipped`,通知說明幾期),不然每一期都用今天的價格買,股數/成本全錯。
- 預設轉帳備註改成「定期定額 0050 26.6904股」,不再帶一長串小數股數。
- 報價:`QuoteRefreshNotifier.refreshForStockDcaRules()` 在啟動生成前(最多等
  8 秒)補抓啟用中定期定額標的的報價;以前只抓已持有的標的。
- `updateRuleAndFuture`:
  - transfer/stock_dca 規則第一期之後改「下次執行時間」,新時間晚於最後一期就
    清掉 `generatedUntilAt` 從新時間重新起算(以前完全沒效果),同 Cloud。
    `LocalRecurringRuleRepository.updateRuleFields` 新增 `clearGeneratedUntilAt`。
  - stock_dca 規則不做步驟 2/3(批次改既有 occurrence 轉帳)——那些轉帳是
    StockTrade 連帶的,直接改金額會跟明細對不上。

## UI

- `recurring_stock_rule_editor_page.dart`:
  - 交割帳戶選擇器只列跟證券同幣別的帳戶(`filterCurrency`),存檔再檢查一次;
    換市場/選到別幣別的標的會清掉不同幣別的交割戶;預設交割戶不同幣別就不帶。
  - 打開「自訂手續費」預填帳戶**生效中**的費率(`resolvedFor(market)`,沒自訂
    過就是市場預設 0.1425%/20),以前預填 0/0,不打字存檔就變成免手續費。
  - 費率顯示四捨五入去尾零(0.14250000000000002 → 0.1425)。
  - 下次執行:新建預設明天 09:00;日期選擇器最早只能選今天(編輯時不能早於
    最後一期);編輯時顯示真正的下一期(`nextPendingOccurrence`),不是永遠停在
    第一期的 `nextRunAt`;改日期時同步「每月 N 號」進階規則的 N。
  - 存檔時若已到期(選今天),立刻補抓報價並生成一次,toast 顯示執行了幾期,
    不用等下次開 App。存檔失敗改成 toast,不再是未處理例外。
  - 新增 `initialMarket/initialSymbol/initialName`,給股票交易頁帶入。
- `stock_trade_editor_page.dart`:新增交易時,交易類型 chip 後面多一顆
  「定期定額」ActionChip,帶著已輸入的市場/代號/名稱轉到定期定額頁。
- `investment_holdings_view.dart`:持股頁新增「定期定額計畫」清單(目前帳本、
  這個投資帳戶),顯示頻率/下次扣款/金額,點擊進編輯。
- 設定匯出/匯入(`config_export_service.dart`)帶上六個定期定額欄位;順便修正
  轉帳規則匯出時用 `accountId`(轉帳是 null)導致來源帳戶遺失,改讀
  `fromAccountId`。

## 入口

- 帳戶 → 投資理財帳戶 → 持股頁「定期定額」按鈕 / 「定期定額計畫」清單。
- 帳戶 → 投資理財帳戶 → 新增交易 → 交易類型列最後的「定期定額」。
- 我的 → 週期性收支 → 「股票定期定額」篩選(管理/停用/刪除/看已生成交易)。

## 刻意沒做

- 台股整數股:2026-09-30 已改,見 `2026-09-30-stock-dca-whole-shares.md`。
- 自訂費率仍會再乘上帳戶的手續費折扣(UI 已加說明文字),沒有另開「規則層級
  折扣」。
- 跨幣別定期定額仍不支援,改成建立時就擋,不是到期才失敗。

## 測試

- `test/repositories/recurring_stock_dca_test.dart`:新增 7 個(自動扣繳不處理
  stock_dca、固定 syncId 不重複、Cloud 已生成只推進度、7 天補期上限、單條壞規則
  不中斷整批、push payload 欄位、改下次執行時間重新起算)。
- `test/sync/recurring_rule_apply_test.dart`:新增 pull 保留/缺鍵不沖掉/null 清除。
- `test/services/investment/stock_dca_test.dart`:uuid5 跟 Cloud 對照。
