# 股票定期定額(Recurring Stock DCA)— App 端

## 背景 / 需求
使用者要求新增「定期定額投資」:因為定期定額的手續費規則常常跟單筆買進不
一樣(例如免手續費、或不同的最低手續費),需要能各自設定;同時希望沿用既
有的「週期性收支」管理頁面(`RecurringRuleListPage`),用分類(一般交易 /
股票交易)區分管理。這份文件只涵蓋 App(Flutter)端;BeeCount Cloud(Web)
端尚未實作,見文件最後「已知限制」。

## 資料模型
`RecurringTransactions` 表(v64)新增欄位:
- `kind`(TEXT,預設 `'general'`):`'general'` = 既有語意;`'stock_dca'` =
  股票定期定額。
- `market`/`symbol`/`securityName`:同 `StockTrades` 對應欄位,只有
  `kind='stock_dca'` 才有值。
- `stockFeeRate`/`stockFeeMin`:規則層級的手續費覆寫(nullable)。皆為
  `null` 時到期生成時沿用投資理財帳戶的預設 `InvestmentSettings`
  (`feeRate`/`feeMin`,`feeDiscount` 一律沿用帳戶預設,不開放規則覆寫)。

`kind='stock_dca'` 的規則**必定** `type='transfer'`:`fromAccountId`=交割
帳戶、`toAccountId`=投資理財帳戶、`amount`=每期投入金額(以證券幣別計)。
**v1 不支援交割帳戶跟證券不同幣別**(同既有 transfer 規則本來就沒有
`toAmount` 欄位,無法表達跨幣別金額)。

## 生成邏輯
到期生成時「股數」是未知的(要看當下報價才能算),所以 `kind='stock_dca'`
規則**不走**視窗預生成(`planInitialGeneration`/`refillWindows`)——這點跟
`type='transfer'` 的自動扣繳規則一樣,`LocalRepository.createRule` 的判斷
條件從 `type != 'transfer'` 改成 `type != 'transfer' && kind != 'stock_dca'`
(雖然邏輯上因為 `stock_dca` 一定是 `transfer`,前者已經隱含後者,但寫明兩個
條件是為了讓未來如果 `stock_dca` 改成不強制走 transfer 時,這裡的守門邏輯
不會悄悄跟著失效)。

新增 `LocalRepository.materializeDueStockRules()`(`RecurringRuleRepository`
新方法),跟既有 `materializeDueTransferRules()` 平行,到期當下才逐期生成:
1. 讀本地 `SecurityQuotes` 快取抓 `market`/`symbol` 的報價,沒有報價 → 跳過
   (`RecurringRuleStockSkipReason.quoteUnavailable`)。
2. 手續費 = 用規則覆寫(`stockFeeRate`/`stockFeeMin`)或投資帳戶預設
   (`InvestmentSettings.resolvedFor(market)`)算 `suggestFee(amount, ...)`。
3. 股數 = `amount / price`(允許小數,定期定額本來就是碎股)。
4. 檢查交割帳戶當下記帳餘額 >= `amount + fee`,不夠 → 跳過
   (`insufficientBalance`),不推進進度,下次呼叫重試同一期。
5. 足夠就呼叫既有 `StockTradeRepository.createStockTrade(tradeType: 'buy',
   recurringRuleId: rule.syncId, ...)`——沿用單筆買進的手續費入帳/轉帳建立
   邏輯,不另外重寫一套;新增的 `recurringRuleId` 參數只是把連帶建立的轉帳
   交易的 `recurringRuleId` 欄位補上,好讓「查看已生成交易」清單能反查到。

App 啟動時(`lib/providers/ui_state_providers.dart`)在既有
`refillWindows()`/`materializeDueTransferRules()` 之後多呼叫一次
`materializeDueStockRules()`,跳過的規則同樣用本地通知提醒(用
`ruleId` 當通知 id,同一條規則重複跳過會覆蓋舊通知)。

## UI
- 新增入口:投資理財帳戶的持股頁(`investment_holdings_view.dart`)新增
  「定期定額」按鈕,開啟新頁面
  `lib/pages/investment/recurring_stock_rule_editor_page.dart`
  (`RecurringStockRuleEditorPage`)建立/編輯規則。市場/代號/證券名稱建立後
  鎖定不可改(同 `StockTradeEditorPage` 的既有慣例),可改金額/交割帳戶/
  手續費覆寫/週期/下次執行/結束時間/備註。
- 週期(頻率/間隔/結束方式)欄位直接重用既有的
  `RecurringRuleAdvancedSheet`(強制帶一個非 null 的
  `initialDraft` 讓它預設開在「週期」tab,不顯示「單次」的意義)。
- `RecurringRuleListPage` 新增「全部/一般交易/股票定期定額」三個篩選
  `ChoiceChip`,依 `rule.kind` 過濾;股票規則的卡片圖示/標題改成
  `Icons.trending_up` + 代號/證券名稱,編輯按鈕會先查
  `toAccountId` 對應的投資理財帳戶物件再導去
  `RecurringStockRuleEditorPage`(一般規則維持導去舊的
  `RecurringRuleEditorPage`)。
- 「查看已生成交易」清單裡,股票定期定額規則的每期**不提供**編輯/刪除/
  連同以後按鈕——那個 occurrence 其實是 `StockTrade` 連帶建立的轉帳交易,
  直接改那筆交易會讓 `StockTrades.txSyncId` 對不上,要改請去投資頁的持股
  明細(那邊會把 `StockTrade` 明細跟轉帳一起處理)。改成顯示一行提示文字
  (`recurringStockOccurrenceHint`)。

## 已知限制 / 沒做的部分

> **2026-09-29 更新**:下面第 2 點(跨端欄位沒接同步)已修正,連同多個生成邏輯/UI
> 問題,見 `2026-09-29-stock-dca-fixes.md`。

1. **不支援跨幣別 DCA**:交割帳戶幣別必須等於證券幣別(同既有限制)。
2. **App 與 BeeCount Cloud(Web)各自獨立實作**——`kind`/`market`/`symbol`/
   `stockFeeRate`/`stockFeeMin` 這幾個欄位目前只是「App 本地」跟「Cloud
   projection」各自新增的欄位,沒有做跨端同步的欄位映射(App 的
   `ChangeTracker` 仍照 `entityType: 'recurring_rule'` 記錄整筆規則變更,
   Cloud 那邊會原樣收下這些欄位存進 `read_recurring_rule_projection`,能夠
   正確顯示/管理——只是這次沒有專門驗證跨裝置同步後兩端行為完全一致)。
   Cloud 端實作見 BeeCount Cloud repo
   `docs/STOCK_HOLDINGS_SD.md` §10。
3. 不會把使用者已經在轉帳表單輸入的金額/備註帶到 DCA 規則(這裡是獨立的
   新建流程,不是從既有轉帳表單導過來的)。

## 驗證
- `flutter analyze`:全專案 0 error。
- `flutter test`:新增
  `test/repositories/recurring_stock_dca_test.dart`(5 個測試,涵蓋不預生成
  /報價齊全生成/報價缺失跳過/餘額不足跳過/手續費覆寫),加上既有
  `test/repositories/recurring_rule_repository_test.dart`、
  `test/data/migration_v62_test.dart`、`test/widgets/recurring_rule_*`、
  `test/widgets/transfer_form_recurring_edit_test.dart` 等既有測試套件全數
  通過(399 tests passed)。
