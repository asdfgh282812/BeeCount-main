# 週期性交易第二輪實機修正(截止日期崩潰、編輯彈窗入口、Tab 表單真同步)

延續 [2026-08-17-recurring-transactions-followup-fixes.md](2026-08-17-recurring-transactions-followup-fixes.md)
——上一版修完後使用者再次實機測試,發現三個問題仍在(其中第 3 項是上一版
修法本身就不夠,不是回歸)。

## 1. 「進階設定」選截止日期時 App 崩潰(table_calendar 斷言失敗)

**根因**:`lib/widgets/ui/entry_date_time_picker.dart` 的
`_TransactionDatePickerSheetState` 不管在 `initState`、`_applyJump`、
`_jumpToToday`、`onDaySelected`、`onPageChanged` 哪個地方,只要要換月都無條
件把 `_focusedMonth` 正規化成「該日期所在月份的 1 號」
(`DateTime(d.year, d.month, 1)`),完全沒管 `firstDay`(=呼叫端傳的
`minDate`)。

`recurring_rule_advanced_sheet.dart` 的「截止日期」選擇器呼叫
`showTransactionDatePicker(minDate: widget.anchorDate)`——`anchorDate`
是週期規則的起始日,幾乎必然不是月初(範例:2026/8/17)。使用者一進日期
選擇器,`initState` 算出 `_focusedMonth = DateTime(2026, 8, 1)`,但傳給
`TableCalendar` 的 `firstDay` 是 `minDate = 2026/8/17`——`focusedDay`
(8/1)早於 `firstDay`(8/17),直接踩中 `table_calendar_base.dart:77` 的
`isSameDay(focusedDay, firstDay) || focusedDay.isAfter(firstDay)` 斷言,紅
屏崩潰。

**修法**:新增私有方法 `_monthStart(DateTime d) => _clamp(DateTime(d.year,
d.month, 1))`,取代所有直接寫 `DateTime(x.year, x.month, 1)` 的地方——先算
月初,再用既有的 `_clamp`(夾在 `[minDate, maxDate]` 之間)夾一次。
`minDate` 不是月初時,月初會被夾到 `minDate` 本身,`focusedDay` 永遠不會早
於 `firstDay`。

測試:`test/widgets/recurring_rule_advanced_sheet_test.dart` 新增一個回歸
測試,用 `anchorDate = 2026/3/10`(月中)走到「截止日期」模式後,真的點開
日期顯示叫出 `TableCalendar` 子選擇器,斷言 `tester.takeException()` 為
`null`——修復前這個測試會直接因為斷言失敗掛掉。

## 2. 編輯週期 occurrence 時,「修改此記錄/連同未來週期」彈窗太晚跳出

**問題**:上一版把選擇彈窗接進了存檔那一刻(`transaction_editor_page.dart`
的 `_handleSubmit`、`transfer_form.dart` 的 `_submit`)——使用者從交易明細
頁點編輯鉛筆,是直接進完整表單頁面,填完資料按確定才看到彈窗。體感上像是
「完全沒有彈窗」,跟 MOZE 參考截圖「一點編輯就先問」的語意不一致。

**修法**:把「問使用者」這一步從存檔時挪到編輯入口:

- `lib/utils/transaction_edit_utils.dart` 的 `editTransaction`——`push`
  `TransactionEditorPage` **之前**,先判斷 `transaction.recurringRuleId !=
  null`,是的話呼叫 `showRecurringEditChoiceSheet`,取消就直接 `return`
  不進頁面。選好的 `RecurringEditScope` 透過新參數
  `initialRecurringEditScope` 帶進 `TransactionEditorPage`。
- `lib/pages/ai/ai_chat_page.dart` 的 `_handleEdit`——AI 對話頁的帳單卡片
  「編輯」入口沒有走 `TransactionEditUtils.editTransaction`(自己
  `push` `TransactionEditorPage`),補上同一段判斷邏輯。
- `TransactionEditorPage` 新增 `initialRecurringEditScope` 欄位,轉發給
  `TransferForm` 的新參數 `recurringEditScope`；`_handleSubmit` /
  `TransferForm._submit()` 改成優先讀這個已經問過的結果,不再重問。
- **安全網**:`_handleSubmit` / `_submit()` 仍保留「如果呼叫端沒有預先問
  (`recurringEditScope == null`)但這筆確實是週期 occurrence,存檔前補問
  一次」的邏輯——這樣 `test/widgets/transfer_form_recurring_edit_test.dart`
  這類直接建構 `TransferForm`(略過入口)的既有測試不用改,也讓任何未來
  忘記在入口先問的呼叫端不會整個跳過選擇直接單筆覆寫。
- `TransactionDetailCard._handleEdit`、`account_detail_page.dart` 的
  「快速轉帳」入口都是走 `showTransactionDetailCard` →
  `TransactionEditUtils.editTransaction`,自動吃到這次修正,不用個別改。

## 3. 支出/收入/轉帳三個 Tab 各自獨立,切換不會互相帶入已輸入的欄位

**根因**:上一版只加了 `AutomaticKeepAliveClientMixin`(見上一份 changes
文件的第 3 項),解決的是「切走再切回來,自己那份輸入不會被清空」——但
三個 Tab 從頭到尾就是三個獨立的 `State`(各自的 `TextEditingController`、
`_selectedAccountId`、`_selectedTagIds`...),KeepAlive 完全不會讓「支出」
輸入的金額/名稱/商家出現在「收入」Tab,兩邊本來就是分開存的,不是同一份
資料被清空,而是從來沒同步過。

**修法**:沒有整個把三個表單的狀態提升到父層(`TransactionEntryForm` /
`TransferForm` 各自 1600+/1100+ 行,獨立維護幣別/回饋規則/附件等大量分頁
特有邏輯,硬拆分風險與改動量都偏大),改用「切 Tab 時做一次快照同步」:

- 新增 `lib/widgets/biz/shared_entry_fields.dart`:`SharedEntryFields` 是一
  個 record typedef,只涵蓋三個分頁概念上共通的欄位——金額(`amountStr` +
  計算機的 `amountAcc`/`amountOp`)、日期時間、名稱(`note`)、商家、標籤、
  帳戶(`accountId`)。類別、附件、幣別、信用卡回饋規則等分頁特有或語意不
  同的欄位不同步。
- `TransactionEntryFormState`(原本是 private 的
  `_TransactionEntryFormState`,改成公開類別給外部 `GlobalKey` 用)跟
  `TransferFormState`(同理,原 `_TransferFormState`)都新增
  `exportSharedFields()` / `applySharedFields()` 這對方法。`accountId`
  對支出/收入是 `_selectedAccountId`;對轉帳是**轉出帳戶**
  `_fromAccountId`——轉入帳戶語意上不是「選中的帳戶」,不參與同步,套用時
  也會擋掉「同步進來的帳戶剛好等於目前轉入帳戶」這種會做出 from==to 的情
  況。套用新帳戶時沿用各自既有的「換帳戶」流程(`_loadSelectedAccount` /
  `_loadAccount`),幣種/名稱/類型會重新載入,支出/收入這邊換帳戶還會照舊
  清掉已選的信用卡回饋規則(規則綁定特定帳戶,換帳戶後舊選擇可能不再合法)。
- `TransactionEditorPage` 用三個 `GlobalKey`(`_expenseFormKey` /
  `_incomeFormKey` / `_transferFormKey`)分別接到三個分頁 widget 上,
  `TabController` 除了原本的 `_unfocusOnTabSwitch` 監聽,再加一個
  `_syncSharedFieldsOnTabChange`:比對 `_tab.index` 是否真的變了(比
  `indexIsChanging` 準——那個只反映動畫有沒有在跑,用來擋反而會在動畫結
  束又多觸發一次),變了就把離開的分頁 `exportSharedFields()`、套用到新切
  到的分頁 `applySharedFields()`。頁面剛開啟時 `_lastTabIndex` 在
  `initState` 設定完初始 tab 之後才記錄,不會在載入當下就誤觸發一次同步、
  蓋掉編輯模式帶入的原始資料。

**已知取捨**:同步是「離開哪個 Tab 就把那個 Tab 的當下狀態整份覆蓋過去」
(單向、覆蓋式),不是雙向合併。如果使用者在支出/收入兩個 Tab 都個別輸入
了不同資料,來回切換會互相覆蓋、以最後一次切出的 Tab 為準——這跟 MOZE 參
考截圖「三個 Tab 本來就是同一份草稿在切分類視角」的語意一致,且比「只同
步某些欄位、其餘各自保留」更容易讓使用者預期。

## 驗證

`flutter analyze`：本次改動的檔案沒有新增 warning/info(既有的
`unnecessary_non_null_assertion`、`deprecated_member_use` 等都是改動前就
存在,行號比對過)。

`flutter test`：695/695 全過(較上一版 694 個新增 1 個:第 1 項的
`table_calendar` 崩潰回歸測試)。`test/widgets/transfer_form_recurring_edit_test.dart`
(第 2 項改動前就存在的測試)、`test/widgets/transaction_entry_form_test.dart`、
`test/widgets/transfer_form_account_hidden_test.dart`、
`test/widgets/amount_editor_currency_test.dart` 等直接建構
`TransactionEntryForm`/`TransferForm`(繞過真正呼叫入口)的既有測試全部
維持通過,靠的就是第 2 項提到的「呼叫端沒先問就在存檔時補問」安全網,以及
第 3 項新增的公開方法是加法、沒有改動既有 constructor 參數的必填性。

沙盒環境沒有可用的 iOS 模擬器/Android SDK(`xcode-select` 未指向
Xcode.app,修正需要使用者 sudo 密碼),三個問題都是程式碼審查 + widget
test 驗證,**沒有做過模擬器/實機手動驗證**——這點跟上一版文件的限制一致,
提醒後續如果又發現偏差,先假設是這裡沒覆蓋到的互動細節。
