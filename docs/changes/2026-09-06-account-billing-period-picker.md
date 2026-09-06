# 帳戶頁信用卡帳單週期支援「選擇區間」清單

## 動機

帳戶頁「交易明細」tab 的信用卡帳單彙總卡片原本只有左右箭頭一期一期切換帳期，
要回顧半年前的帳單得點很多下。專案頁已經有「選擇區間」清單彈窗（點期間文字
直接列出過去 12 期供選擇），這次把同一套 UI 搬到帳戶頁。

## 變更

- `lib/widgets/ui/period_range_selector.dart`：新增
  `showBillingCyclePeriodListPicker()`，跟既有 `showPeriodRangeListPicker()`
  共用同一個 `_PeriodRangeListPickerSheet` 彈窗 UI，差別只在週期用
  `billingCyclePeriod()`（結帳日週期）而不是自然月/年算（回溯範圍後來改成
  資料驅動，見下方「追加修正」）。沿用
  既有的 `projectPeriodPickerTitle`（「選擇區間」）l10n key，文字本來就沒有
  專案專屬字眼，不另外加 key。
- `lib/pages/account/account_detail_page.dart`：`_buildBillingSummaryCard()`
  的週期導航從手寫的 `Row`（IconButton + 純文字 `Text`）換成共用元件
  `PeriodRangeSelector`，並新增 `_openBillingPeriodPicker()` 接
  `onTapLabel`，選中後 `setState` 更新 `_billingPeriodOffset`（跟箭頭導航
  共用同一個 state 欄位，兩種切法互通)。

## 範圍外

- 只動了「交易明細」tab 的帳單彙總卡頭（帳戶頁目前唯一一處帳期 chevron
  導航）；「帳戶資訊」tab 沒有獨立的帳期切換 UI，不受影響。

## 追加修正（同日，使用者實測回報）

1. **清單不該列出沒有資料的更舊帳期**：原本無條件往回列 12 期，新帳戶/新
   卡會列出一堆空清單項目。改成 `_openBillingPeriodPicker()` 先用
   `AccountRepository.getCreditCardFirstActivityAt()`（合併帳單群組要對每個
   子帳戶都查，取最早）反推最舊有資料的帳期 `oldestOffset`，只往回列到那裡
   ——跟 `credit_card_billing_providers.dart` 的
   `creditCardPaymentPeriodRecordsProvider` 找 `oldestOffset` 是同一套算法。
   `showBillingCyclePeriodListPicker()` 因此把寫死的 `-12` 改成呼叫端傳入的
   `oldestOffset` 參數（仍會跟目前選中的 offset 取更舊者，確保選中項一定在
   清單裡）。`account.createdAt` 不可靠（舊資料可能是 null），沒有用它當
   備援。

2. **一般帳戶/合併帳單主帳戶（`account_group`）沒設 `billingDay` 時，週期
   應該對齊帳本的月結日，而不是寫死每月 1 號**：`billingCyclePeriod()` 本來
   在 `billingDay == null` 時退化成「每月 1 號」，這對真的信用卡沒差（一定有
   `billingDay`），但 `_buildBillingSummaryCard` 這個分支同時服務
   `account.type == 'account_group'`（合併帳單主帳戶/一般帳戶群組容器，見
   `account_detail_page.dart:382-388` 的說明），這類帳戶通常沒有真的銀行結帳
   日，退化成「每月 1 號」會跟使用者在帳本設定的 `monthStartDay` 對不上。新增
   `_effectiveBillingDay(account)` = `account.billingDay ??
   currentLedgerProvider.monthStartDay`，套用在「交易明細」tab 所有跟這個
   共用帳期概念相關的呼叫點（`_billingPeriod`、
   `defaultBillingPeriodOffsetProvider`、`accountStatementTransactionsProvider`
   ×2、`creditCardPaymentPeriodRecordsProvider`、
   `cardRewardAccountSummaryProvider`、選擇區間清單）。**沒有**套用在
   「應繳日期」（`_dueDate`）、「帳戶資訊」tab 顯示帳單日/繳款日的欄位——這些
   本來就只在 `account.billingDay != null`（真的信用卡）時才顯示，語意上不該
   對齊帳本月結日退化顯示，維持原樣。
