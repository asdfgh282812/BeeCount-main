# 修正 App 端信用卡繳款轉帳的備註/分類與網頁端(BeeCount Cloud)不一致

## 問題

使用者反饋：在 App 對「單卡」（非合併帳單群組）信用卡按「繳款記錄」建立的轉帳交易，跟在 BeeCount Cloud 網頁端做同一件事產生的轉帳交易，行為不一致：

- 網頁端：備註寫成 `信用卡繳款(帳單 2026-08-11~2026-09-11)`，分類為空。
- App 端：備註只有純日期區間 `2026/08/05-2026/09/05`，分類顯示簡體「转账」（App 其他地方的轉帳交易分類都應顯示繁體「轉帳」）。

## 原因

兩個各自獨立的問題，都只發生在單卡繳款路徑（[account_detail_page.dart](../../lib/pages/account/account_detail_page.dart) 的 `_onAddPaymentRecord`，`children.isEmpty` 分支）：

1. **備註文字**：該分支呼叫的是純顯示用的 `_formatCycleLabel(period)`（純日期區間），而不是 `lib/utils/credit_card_payment.dart` 裡逐字對齊 BeeCount Cloud `card_payment_ep` 的 `creditCardPaymentNote()`。合併帳單群組路徑（[credit_card_group_payment_page.dart](../../lib/pages/account/credit_card_group_payment_page.dart)）本來就正確呼叫了 `creditCardPaymentNote()`，只有單卡路徑漏掉。

2. **分類名稱**：轉帳交易的分類一律取自「虛擬轉帳分類」（`kind='transfer'`），正常情況下 seed 時就已用 `l10n.transferTitle` 本地化建立好。但 [local_category_repository.dart](../../lib/data/repositories/local/local_category_repository.dart) 的 `getTransferCategory()` 裡有一段「理論上不該發生、但萬一分類被清空時」的兜底自建邏輯，寫死插入 `name: '转账'`（簡體字面量，不看使用者語言）。一旦這個兜底邏輯被觸發過一次，該分類名稱就永久卡在簡體，直到手動修正——這正是使用者畫面上看到的情況。

## 修復

- [account_detail_page.dart:1750](../../lib/pages/account/account_detail_page.dart) 單卡分支改呼叫 `creditCardPaymentNote(billingDay: account.billingDay)`，跟合併帳單群組路徑及網頁端一致。
- [local_category_repository.dart](../../lib/data/repositories/local/local_category_repository.dart) 的兜底自建邏輯改用 `lookupAppLocalizations(PlatformDispatcher.instance.locale).transferTitle`（`dart:ui`/`AppLocalizations` 的 non-BuildContext 用法，沿用 `auto_billing_service.dart` 既有的同類寫法），不再寫死簡體。
- 另外在 [local_repository.dart](../../lib/data/repositories/local/local_repository.dart) 的 `getTransferCategory()` 加了 `_healTransferCategoryName()`：每次取用轉帳分類時，若目前名稱精確等於舊版寫死的字面量 `'转账'`、且當前語言的本地化名稱不同，就順手改寫成正確名稱並透過 `changeTracker.recordUserGlobalChange` 記錄變更（`category` 是 user-global 實體，`ledgerId=0`），讓已經被這個歷史 bug 污染過的既有使用者（例如回報問題的這位使用者）下次繳款/編輯轉帳時自動修正，不需要資料庫 migration。刻意只在名稱「精確等於」那個舊字面量時才改寫，避免誤改使用者本身就是簡體中文語言、或曾手動把這個虛擬分類改名的情況。

## 範圍之外

- 網頁端（BeeCount Cloud）分類欄位維持顯示為空，未去對齊——這是網頁端自己的既有行為，此次只處理 App 端貼齊網頁端「有意義備註 + 正確分類語言」的部分，不是要求兩端分類欄位完全相同的視覺呈現。
- 沒有新增 schema migration；`_healTransferCategoryName` 的自癒是執行期邏輯，不影響 `schemaVersion`。
