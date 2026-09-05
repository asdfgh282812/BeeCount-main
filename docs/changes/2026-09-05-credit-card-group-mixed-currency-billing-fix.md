# 合併帳單群組跨幣別子卡的帳單彙總金額錯誤修正

使用者反饋（2026-09-05）：合併帳單群組（`account_group`，見
[2026-09-05-credit-card-billing-group-accounts.md](2026-09-05-credit-card-billing-group-accounts.md)）
底下掛了一張 JPY 子卡（永豐幣倍卡）時，帳戶詳情頁「帳單彙總」卡片的
「新增花費」「應繳金額」把這張子卡的 JPY 原始數字直接當成 TWD（帳本本位幣）
加進總額，數字爆量失真；使用者同時指出 BeeCount Cloud（server 端）有同樣的
問題，但那是獨立 repo，這次只處理 App 端。

## 根因

`account_edit_page.dart` 的「主帳戶候選清單」（見上述設計文件 §3）刻意不做
子帳戶幣別一致性檢查（server 端允許混合，有測試鎖住這個行為），所以合併
帳單群組的子卡彼此幣別不同是完全合法、預期會發生的情境。但帳單彙總的整條
計算鏈——`account_detail_page.dart::_buildBillingSummaryRows` 的
`newSpending`/`rewardThisPeriod` 迴圈、
`local_account_repository.dart::getCreditCardChargedAsOf`/
`getCreditCardPaidTotal`——全部是把「主帳戶 + 所有子帳戶」的交易 `amount`
欄位直接相加，完全沒有做幣別換算，只是套用主帳戶自己的 `currency` 欄位當
顯示標籤。單一（非群組）信用卡不會踩到這個問題，因為記帳表單本身保證
「帳戶內不混幣」（`transaction_entry_form.dart::_txCurrency()`），但群組彙總
是跨帳戶相加，這個保證跨不過帳戶邊界。

## 修正

沿用交易表 v30 既有的 `nativeAmount`（記帳當下就折算好的「本位幣快照」，
見 [db.dart:174-182](../../lib/data/db.dart)）作為換算依據，不重新查即時匯率：

- [account_repository.dart](../../lib/data/repositories/account_repository.dart)：
  `getCreditCardChargedAsOf` 新增 `convertToLedgerCurrency` 參數（預設
  `false`，維持單卡頁面原本行為不變）。
- [local_account_repository.dart](../../lib/data/repositories/local/local_account_repository.dart)：
  該參數為 `true` 時，SQL 一併查出 `native_amount`，逐筆改用
  `native_amount ?? amount` 加總。
- [credit_card_billing_providers.dart](../../lib/providers/credit_card_billing_providers.dart)：
  `_dueAsOf`/`_periodNewSpend`（分別餵「上期欠款/剩餘帳款/可繳款徽章」跟
  「新增花費」）依 `ids.length > 1` 判斷是否為合併帳單群組，是的話對每個子
  帳戶都傳 `convertToLedgerCurrency: true`；單一帳戶維持 `false`。
- [account_detail_page.dart](../../lib/pages/account/account_detail_page.dart)：
  `_buildBillingSummaryRows` 比照同一套邏輯——`children.isNotEmpty` 時，
  彙總改讀 `tx.nativeAmount ?? tx.amount`，畫面顯示的幣別也從
  `account.currency`（群組容器自己選的、不代表任何實際換算結果）改成
  `currentLedgerCurrencyProvider`（帳本本位幣，正好對應 `nativeAmount`
  折算的目標幣別）；單一帳戶維持讀 `tx.amount` + 自己的 `account.currency`。

順手修正同一個檔案裡的另一個獨立小 bug：`getCreditCardPaidTotal`（已繳金額）
跟 `attributePaymentsToPeriods` 呼叫端原本讀轉帳交易的 `amount`（轉出方
幣別的數字），改讀 `toAmount ?? amount`（轉入方——也就是這張卡——實際入帳
的金額）。兩者在同幣別轉帳時相等，只有跨幣別轉帳才會有差異，跟本次幣別
換算問題同源但獨立，一併修正。

## 明確排除範圍

- **繳款轉入金額的本位幣換算**：`toAmount` 沒有像 `nativeAmount` 一樣預先
  存好的「折算到帳本本位幣」快照（`nativeAmount` 只對應交易來源端幣別），
  要精確換算需要即時查匯率表，牽涉的改動（把 `ExchangeRateRepository`/
  `effectiveRatesForLedgerProvider` 接進 repository 層）明顯超出這次回報的
  症狀範圍（使用者截圖裡「已繳金額」是 0，這次沒有實際繳款要換算）。合併
  帳單群組如果子卡幣別跟繳款轉入的幣別不同，「上期欠款/剩餘帳款」仍可能有
  殘餘誤差，留待之後有實際案例再處理。
- **`credit_card_group_payment_page.dart`（合併帳單一次繳款頁）**：這個頁面
  本來就在文件註解裡明確排除「子卡跨幣別時不做匯率換算」，是獨立、刻意的
  既有限制，這次不動。
- **可用額度／淨值估值等其他跨子卡彙總數字**：只確認並修正「帳單彙總卡片」
  （新增花費/上期欠款/應繳金額/已繳金額/剩餘帳款）這條鏈,沒有排查頁面上
  其他可能也做跨子卡加總的數字（例如可用額度）是否有同樣的問題。
- **BeeCount Cloud（server 端）**：使用者提到 server 有同樣的問題，但那是
  獨立 repo（`../BeeCount-Cloud/`），這次不處理。

## 驗證

`flutter analyze`（相關檔案無新增錯誤/警告）；`flutter test`（全數
1125 個測試通過，含既有的
`test/repositories/credit_card_charged_deferred_posting_test.dart`、
`test/repositories/account_transactions_aggregate_test.dart`（主卡+子卡
聚合）、`test/providers/credit_card_payment_period_records_provider_test.dart`、
`test/repositories/local/installment_repository_test.dart` 等信用卡帳單/
分期相關測試，`convertToLedgerCurrency` 預設 `false` 不影響既有單卡測試）。
未新增涵蓋「群組子卡跨幣別」情境的自動化測試——沒有能重現使用者實際資料
（永豐信用卡群組 + JPY 子卡）的既有測試 fixture 可以擴充，之後若要補測試
建議照 `account_transactions_aggregate_test.dart` 的既有模式,額外插入一張
不同 `currency`/`nativeAmount` 的子卡交易。未能在本機做 iOS 模擬器/瀏覽器
即時畫面驗證（環境限制，同上一篇文件所述）。
