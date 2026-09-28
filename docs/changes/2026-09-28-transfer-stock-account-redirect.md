# 轉帳選到股票帳戶時導向買進/賣出

日期:2026-09-28
跨 repo:本 repo(App)+ BeeCount Cloud(`/Users/andy/BeeCount-Cloud`,server + Web)。
Cloud 端見 `BeeCount-Cloud/docs/STOCK_HOLDINGS_SD.md` §9。

之前轉帳表單(App、Web 都一樣)沒有特別處理投資理財帳戶:選到之後就是一筆
「金額對得上、股數對不上」的裸轉帳,不會建立 `stock_trade` 明細,持股/成本
完全不會變。這次改成:**轉入帳戶選到投資理財帳戶 → 買進;轉出帳戶選到投資
理財帳戶 → 賣出**,另一側已經選好的帳戶直接帶當交割戶。

## App(`lib/widgets/transaction/transfer_form.dart`)

`_pickAccount` 選完帳戶後多一段檢查:選中的帳戶(轉入用 `!isFrom`、轉出用
`isFrom` 判斷買/賣)`type == 'investment'` 就呼叫新增的 `_redirectToStockTrade`,
push `StockTradeEditorPage`(買進/賣出),`initialSettlement` 帶另一側已選的
帳戶。存檔成功(`pop(true)`)視同這筆轉帳已完成,呼叫
`widget.onTransferComplete()` 直接關掉整個交易編輯器;取消的話把剛選的投資
理財帳戶欄位退回未選,轉帳表單其它欄位(金額/備註/日期…)不受影響。

`StockTradeEditorPage` 新增 `initialSettlement`(`Account?`)建構參數,有帶的話
`initState` 直接用它當交割戶,跳過原本的 `_loadDefaultSettlement()` 反查
邏輯。

只在 `_pickAccount`(使用者主動選)裡判斷——編輯既有轉帳時單純載入既有帳戶
顯示(`_loadAccount`)不會觸發,避免打開一筆舊資料(這個功能上線前建立、沒有
`stock_trade` 的裸轉帳)就被強制導去買賣頁。編輯時使用者若主動把帳戶改成別的
投資理財帳戶,一樣會導向——這種情況下原本在編輯的轉帳不會被更新或刪除,等於
留下一筆沒改到的舊轉帳 + 一筆新的股票交易,跟這次改動前「編輯轉帳幾乎不會
選到投資理財帳戶」一樣是邊界案例,不特別處理。

## Web(`TransactionsPage.tsx` + `InvestmentsPage.tsx`)

Web 之前更嚴格:`txWriteAccounts`(交易表單帳戶下拉的候選清單)直接排除所有
「估值帳戶」類型(`real_estate`/`vehicle`/`investment`/`insurance`/
`social_fund`/`loan`),投資理財帳戶連選都選不到,是這次一起修的 bug。改成
`tx_type === 'transfer'` 時額外放行 `investment` 類型(其它估值類型維持排除,
跟本次功能無關)。

放行之後,選到投資理財帳戶要能跟 App 一樣導去買進/賣出,而不是讓使用者真的
送出裸轉帳:

- `InvestmentsPage.tsx` 的 `StockTradeDialog`/`TradeDialogState`/`CreatableType`
  改成 `export`,多一個 `TradeDialogState.initialSettlementAccountId` 欄位
  (優先於帳戶費用設定裡的預設交割戶),`TradeDialogState.initial.market`/
  `symbol` 改成可選(轉帳導過來時還沒有代號可以帶)。
- `TransactionsPage.tsx` 新增一個 `useEffect`,監看 `txForm.from_account_name`/
  `to_account_name`(表單存的是名稱,不是 id,對齊 `onSaveTransaction` 既有的
  查表方式)。判斷出買/賣後,先用 `fetchWorkspaceHoldings({accountId, refresh:
  false})` 拉這檔的持股(賣出時 client 端的賣超檢查要用,server 端
  `stock_trades.py` 還會再驗一次),再開 `StockTradeDialog`,`activeLedgerId`
  傳目前寫入的帳本(`txContextLedgerId`),不是側邊欄目前選的帳本。
- **編輯既有交易時的防呆**:跟 App 用「使用者主動選」當判斷條件不同,Web 表單
  帳戶欄位是單純的 state,打開編輯既有轉帳時沒有天然的「這是使用者剛選的」
  訊號。改用 `txTransferAccountsAtOpen`(對話框打開那一刻的兩個帳戶名稱基準)
  ——目前值跟基準一樣就當作「還沒被改過」略過,使用者真的把某一側改成別的
  投資理財帳戶時才導向,語意對齊 App 的「只在主動選時觸發」。
- 存檔成功關掉 `StockTradeDialog` 之後,連整個交易 dialog 一併關掉並刷新列表
  (`onRefresh()`);使用者取消的話只清掉剛選的那一側帳戶名稱,表單其它欄位
  不動。

## 沒做的部分

Web 的 `StockTradeDialog` 沒有「新增交易時自動帶入現價」以外的表單簡化——
從轉帳導過去之後,使用者還是要自己選市場/輸入代號,跟直接在「投資」頁按
「新增交易」的體驗一樣,沒有另外做「帶入交易描述/金額」之類的欄位預填
(App 端也沒做,兩邊一致)。
