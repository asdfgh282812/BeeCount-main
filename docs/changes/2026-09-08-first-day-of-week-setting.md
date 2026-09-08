# 新增「每週起始日」設定(週一/週日)

## 背景

App 內所有日曆/日期選擇器過去都寫死以週一為一週的第一天。新增設定讓使用者可以
切換成週日起始,並讓相關的日期選擇器與顯示器同步套用。

## 新設定:`weekStartsOnMondayProvider`

- [lib/providers/theme_providers.dart](../../lib/providers/theme_providers.dart) —
  比照 `showTransactionTimeProvider` 的既有模式新增 `weekStartsOnMondayProvider`
  (`StateProvider<bool>`,預設 `true`,與歷史行為一致)+
  `weekStartsOnMondayInitProvider`(啟動時讀回 SharedPreferences `weekStartsOnMonday`
  鍵,並用 `ref.listen` 寫回本機 + 觸發 `_pushAppearanceToCloud`)。
- `_pushAppearanceToCloud` 的 `appearance` map 新增 `week_starts_monday` 欄位,
  和主題色、字體大小等外觀設定一樣自動同步到雲端 profile,換裝置登入後套用。
- [lib/providers/sync_providers.dart](../../lib/providers/sync_providers.dart) 的
  `_applyAppearanceFields`(下行套用)與 `reconcileProfileToServer`(首次同步時
  補推本機值)都新增對應處理,呼叫端
  ([sync_providers.dart](../../lib/providers/sync_providers.dart)、
  [beecount_cloud_sync_page.dart](../../lib/pages/cloud/beecount_cloud_sync_page.dart))
  一併補上 `currentWeekStartsOnMonday` 參數。
- 啟動預載清單([ui_state_providers.dart](../../lib/providers/ui_state_providers.dart))
  與匯入設定後的 provider 失效清單([welcome_page.dart](../../lib/pages/auth/welcome_page.dart))
  都加入這個新的 init provider。

## 日曆與日期選擇器接上設定

- [lib/pages/calendar/calendar_body.dart](../../lib/pages/calendar/calendar_body.dart) —
  記帳頁「明細」tab 的月曆/週曆,`TableCalendar.startingDayOfWeek` 改為讀
  `weekStartsOnMondayProvider`。
- [lib/widgets/ui/entry_date_time_picker.dart](../../lib/widgets/ui/entry_date_time_picker.dart) —
  原本專供交易表單使用的 `showTransactionDatePicker` 通用化並更名為
  `showAppDatePicker`(簽名不變:`initial`/`minDate`/`maxDate`),內部
  `_TransactionDatePickerSheet` 改為 `ConsumerStatefulWidget` 讀取同一個設定。

### 取代原生 `showDatePicker`

Flutter 原生 `showDatePicker` 的週起始日是綁在 `MaterialLocalizations`(跟隨
`Locale`),沒有獨立參數可覆寫;要通用轉發整個 `MaterialLocalizations` 介面
(近 80 個成員)在 Dart 沒有 mirrors/反射的情況下不可行,且會綁死 Flutter SDK
內部實作、升級容易壞掉。因此改為把 App 內全部 12 處原生 `showDatePicker`
呼叫,換成上面通用化後的 `showAppDatePicker`:

- `lib/pages/project/project_edit_page.dart`
- `lib/pages/debt/debt_editor_page.dart`
- `lib/pages/debt/debt_repayment_page.dart`
- `lib/pages/account/card_reward_rule_editor_page.dart`
- `lib/pages/account/account_reconciliation_page.dart`
- `lib/pages/installment/installment_editor_page.dart`
- `lib/widgets/biz/installment_edit_choice_dialog.dart`
- `lib/widgets/biz/installment_action_sheets.dart`(3 處)
- `lib/widgets/transaction/debt_entry_form.dart`

副作用(刻意接受,已在設計討論階段確認):這些編輯頁的日期選擇器外觀從「原生
Material 日期對話框」統一變成「App 自訂的深色 bottom sheet」,與記帳表單的
日期欄位樣式一致。原生 `helpText` 等專屬參數捨棄(新元件標題固定「選擇日期」)。

## 設定頁 UI

[lib/pages/settings/appearance_settings_page.dart](../../lib/pages/settings/appearance_settings_page.dart)
新增「每週起始日」列(標題 `appearanceFirstDayOfWeek`),點擊彈出週一/週日
兩選一對話框,樣式比照既有「備註顯示方式」設定列(`_showNoteDisplayDialog`)。
選項標籤重用既有的 `commonWeekdayMonday`/`commonWeekdaySunday`,未新增額外
l10n key。

## 刻意不動的部分

- `lib/widgets/biz/recurring_rule_advanced_sheet.dart` 的「重複於星期幾」
  核取方塊,固定以一二三四五六日順序顯示——這是「選擇星期幾」而非日曆格狀
  排列,維持固定順序較好辨識,且底層資料仍是 `recurring_rule_schedule.dart`
  的 Monday=0 慣例,不受這個設定影響。
- `lib/widgets/ui/wheel_date_picker.dart`(年月 wheel 跳轉)沒有星期概念,
  不受影響。

## 本地化

依既有政策只更新 `app_en.arb` + `app_zh_TW.arb`,不更新 `app_zh.arb`/`app_ko.arb`。

## 測試

新增 [test/widgets/first_day_of_week_test.dart](../../test/widgets/first_day_of_week_test.dart)
驗證 `weekStartsOnMondayProvider` 切換後,`calendar_body.dart` 與
`showAppDatePicker` 內的 `TableCalendar.startingDayOfWeek` 都正確跟著變。

順帶修正
[test/widgets/recurring_rule_advanced_sheet_test.dart](../../test/widgets/recurring_rule_advanced_sheet_test.dart)——
`showAppDatePicker` 底層元件改成 `ConsumerStatefulWidget` 後需要
`ProviderScope` 祖先,原本這個測試檔沒有包,補上後恢復通過。
