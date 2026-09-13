# AI 記帳:外幣收據選了不同幣種帳戶,修正換算 + 帳戶選單

## 問題

使用者拍一張日圓(JPY)收據,AI 正確辨識出幣種是 JPY,但落地到記帳時有兩個 bug:

1. AI 找不到 JPY 帳戶,跳出「選擇帳戶」讓使用者手動挑,使用者選了一個台幣
   (TWD)帳戶——交易確實以 TWD 落庫,但金額是 AI 抓到的 JPY 原始數字,沒有按
   匯率換算,等於把「10230 日圓」直接記成「10230 台幣」。
2. 使用者其實有 JPY 帳戶,想在「選擇帳戶」畫面直接選它,但畫面上根本沒有列出
   JPY 帳戶可選(只列出跟帳本本位幣同幣種的帳戶)。

## 根因

- `lib/services/billing/bill_creation_service.dart` `createFromBill` 第 4.5
  步:帳戶一旦命中(不管是自動匹配還是使用者手動選的),交易幣種
  (`currencyCode`)一律跟著帳戶幣種走(帳戶內不混幣的不變量)。自動匹配路徑
  (`_matchAccountByName`)本身就按 `requestedCurrency` 篩過候選池,所以命中的
  帳戶幣種必然等於 AI 給的幣種,這條分支原本不會遇到幣種衝突。但
  `resolveMissingAccount` 回調(AI 找不到帳戶、跳出選擇 sheet 讓使用者手動挑)
  沒有這層篩選——使用者可以選任何幣種的帳戶。落庫時只是把衝突記一行警告
  log,金額(`amount.abs()`)完全沒有换算,直接照 AI 給的原始數字塞進去。
- `AccountCardPicker.show` 的三個 AI 呼叫點(`image_billing_helper.dart`
  `voice_billing_helper.dart` `ai_chat_page.dart` 的 `resolveMissingAccount`
  回調)都沒有傳 `allowAllCurrencies: true`,預設只顯示「幣種等於帳本本位幣」
  的帳戶。對照手動記帳表單(`transaction_entry_form.dart` 的
  `_openAccountPicker`)一律傳 `allowAllCurrencies: true`,任何幣種的帳戶都能
  選——AI 這三個入口沒有跟著做。

## 修正

- `lib/services/billing/bill_creation_service.dart`:
  - 新增 `_convertBetweenCurrencies`(三角換算,`requestedCurrency → 帳本本位幣
    → accountCurrency`,邏輯對齊 `transfer_form.dart` 既有的
    `_convertCrossCurrency`——本地匯率表只以帳本本位幣為 base,兩個外幣之間沒
    有直接匯率,所以要分兩段轉)+ `_effectiveRates`(讀取某 base 下手動
    override 疊加最新自動匯率,口徑同 `LocalRepository._effectiveRatesFor`)。
  - 第 4.5 步之後新增判斷:命中帳戶的幣種(`accountCurrency`)如果跟 AI 給的
    幣種(`requestedCurrency`)不同,就呼叫上面的三角換算把金額轉成
    `accountCurrency`,再落庫;换算所需的匯率會先嘗試 `_ensureRateAvailable`
    補抓。查無匯率(兩段任一段缺)則保留原本行為——金額原樣落庫、記一行警告,
    不會因為換算失敗擋住整筆交易(維持既有「無人值守不能因為缺匯率丟帳」的
    設計)。
  - 帳戶幣種等於 AI 給的幣種、或其中一個為空,行為完全不變。
- `lib/utils/image_billing_helper.dart` / `lib/utils/voice_billing_helper.dart`
  / `lib/pages/ai/ai_chat_page.dart`:三處 `resolveMissingAccount` 回調裡的
  `AccountCardPicker.show` 都加上 `allowAllCurrencies: true`,跟手動記帳表單
  的帳戶選單行為對齊——任何幣種的帳戶都能在這裡選到。
- `lib/pages/account/pending_account_transactions_page.dart`(「待確認帳戶」
  補選畫面,順手修的同源 bug):這裡的交易 `currencyCode` 在 AI 記帳當下就已
  經定案(可能就是外幣,例如 JPY),補選帳戶不會重算幣種或金額,所以候選帳戶
  必須篩「這筆交易自己的幣種」(`filterCurrency: tx.currencyCode`),而不是帳
  本本位幣——否則日圓記錄的待確認交易,補選帳戶時一樣看不到日圓帳戶。這裡刻
  意沒有用 `allowAllCurrencies: true`(不像上面三個入口),因為這個畫面不會做
  幣種換算,放開成任意幣種只會重新製造「跟這裡的 bug 1 一樣沒換算」的問題。

## 沒有改變的行為

- 帳戶自動匹配(`_matchAccountByName`)本來就按幣種篩池,命中帳戶幣種必然等於
  AI 給的幣種,這條路徑完全不受影響。
- 背景渠道(自動截圖/通知監聽)沒有 `resolveMissingAccount` 回調,不會走到
  這個新的換算分支,行為不變。
- 沒有偵測出幣種(`bill.currency` 為空)或帳戶本身沒設幣種時,行為不變(維持
  原本「都沒有 → 帳本本位幣」的兜底)。

## 測試

`test/services/billing/bill_creation_service_test.dart` 新增 3 個回歸測試
(`resolveMissingAccount` group 內):
- 選的帳戶幣種跟 AI 給的幣種不同 + 有匯率 → 金額按匯率換算成帳戶幣種。
- 選的帳戶幣種既非 AI 幣種、也非帳本本位幣 → 三角換算兩段都要對。
- 沒有匯率時 → 退化成金額原樣記入該帳戶(維持既有「不阻斷」行為)。

未新增 `pending_account_transactions_page.dart` 的 widget 測試(該頁面目前沒有
既有測試檔可掛,修改本身是一行過濾條件替換,风险低)。
