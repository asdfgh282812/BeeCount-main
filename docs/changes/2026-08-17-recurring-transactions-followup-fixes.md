# 週期性交易後續修正(count 直接輸入、截止日期、轉帳編輯選擇彈窗、Tab 切換重置)

延續 [2026-08-17-recurring-transactions-cloud-sync.md](2026-08-17-recurring-transactions-cloud-sync.md)
的 v36 週期性交易功能,修正上線前使用者實測發現的三個問題。

## 1. 進階設定彈窗:次數支援直接輸入 + 新增「截止日期」結束方式

`lib/widgets/biz/recurring_rule_advanced_sheet.dart`:

- 「指定次數」的數字原本只能點 `+`/`-` 調整;數字本身現在包一層
  `InkWell`(`Key('recurringFixedCountValue')`)點擊叫出 `AlertDialog` +
  `TextField(keyboardType: TextInputType.number)`,輸入後直接 `setState`。
- 結束方式從 `bool _unlimited` 改成 `enum _EndMode { unlimited, count,
  date }` 三選一。新增「截止日期」選項,選中後顯示一個可點擊的日期列,呼叫
  既有的 `showTransactionDatePicker`(跟交易表單日期欄位同一顆 widget,樣式
  一致)挑日期,直接寫回 `endAt`,不再透過 `enumerateOccurrences` 反推。
- `RecurringRuleDraft` 本身沒變(仍然只存最終 `endAt`,不記錄是哪種模式選
  出來的)——**已知限制**:重新打開彈窗(`initialDraft` 帶入舊 `endAt`)時
  沒法還原「當初是選次數還是選日期」,一律當「截止日期」模式回顯。這個彈窗
  目前只在「新增交易」流程裡當場使用(選完就送出建規則),不會真的重新打開
  已存在的規則去編輯,所以實務上不影響——影響範圍與現有的其他 v1 範圍限制
  一致,故未進一步處理。
- 新增 l10n key:`recurringCountDate`(截止日期)、
  `recurringCountEditTitle`(次數輸入對話框標題),兩個 arb 檔都加了。
- 測試:`test/widgets/recurring_rule_advanced_sheet_test.dart` 新增 2 個
  interactive widget test(點數字輸入次數、選截止日期模式)。

## 2. 轉帳表單編輯週期 occurrence 完全跳過選擇彈窗(真 bug)

**根因**:v36 上一版只把「修改此記錄/連同未來週期」二選一彈窗接進
`transaction_editor_page.dart` 的 `_handleSubmit`(支出/收入兩個 tab 共用這
段存檔邏輯),但**轉帳分頁 `TransferForm` 有自己獨立的 `_submit()`**,不走
`_handleSubmit`。所以編輯轉帳類型的週期規則(自動扣繳)生成的 occurrence
時,存檔會直接單筆覆寫,完全不會問使用者要改這筆還是連同未來週期——這正是
使用者回報「目前僅能直接編輯該單筆紀錄」的真實成因(支出/收入交易本身沒問
題,轉帳才有)。

`lib/widgets/transaction/transfer_form.dart` 的 `_submit()` 補上跟
`transaction_editor_page.dart` 對稱的邏輯:

- 編輯模式下,先 `getTransactionById` 抓 `recurringRuleId`,非 null 才彈
  `showRecurringEditChoiceSheet`;取消則 `setState(_isSubmitting=false)` 並
  中止存檔(不寫入任何變更)。
- 選「此記錄」:轉帳的 `updateTransaction`/`updateTransactionFields` 照舊執
  行後,直接 flip `recurringOccurrenceOverridden = true`。
- 選「連同未來週期」:額外呼叫既有的 `repo.updateRuleAndFuture(...)`(轉帳
  語意:`categoryId` 不傳,底層 `clearCategoryId: type=='transfer'` 已經處理
  好)。

測試:新增 `test/widgets/transfer_form_recurring_edit_test.dart`(3 個
interactive test,真的用 `LocalRepository` + 記憶體 Drift db 建規則 +
occurrence,pump/tap 走真實 `TransferForm._submit()`)。這幾個測試意外挖出
一個環境限定的坑:`_submit()` 成功路徑會呼叫 `showToast`(2 秒自動關閉
Timer)跟 `TxAuthorService.markEdited`(watch
`beecountCloudProviderInstance`,測試環境沒有真雲端配置永遠 resolve 不了、
連帶 `LoggerService` 的錯誤紀錄又是另一個 2 秒防抖 Timer)——不 mock
`beecountCloudProviderInstance`、不在 `pumpAndSettle` 之外額外流掉這兩個
Timer 的話,`flutter_test` 會在 `tearDown` 判 `pending timer` 失敗,
`pumpAndSettle()` 本身也會因為 `beecountCloudProviderInstance` 的 Future 永
遠不 resolve 而判超時。測試裡改用固定次數的有界 `pump()` + override
`beecountCloudProviderInstance` 解決,不影響生產程式碼行為。

## 3. 新增交易頁面切換 Tab 導致表單重置(真 bug)

**根因**:`TransactionEditorPage` 用一個 `TabBarView` 包三個分頁
(支出/收入各一個 `TransactionEntryForm`、轉帳一個 `TransferForm`)。
`TabBarView(children: [...])` 底層是 `PageView`,用固定 `children` list 建
構時走 `SliverChildListDelegate`,**預設會依捲動快取範圍把捲出畫面的分頁
State 整個丟棄重建**——切到別的 Tab 再切回來,`initState` 重跑,使用者已輸
入的金額/名稱/商家/帳戶/標籤等欄位全部回到初始值,等於被清空。

`lib/widgets/biz/transaction_entry_form.dart` 的 `_TransactionEntryFormState`
與 `lib/widgets/transaction/transfer_form.dart` 的 `_TransferFormState` 都
加上 `AutomaticKeepAliveClientMixin`(`wantKeepAlive => true` +
`build()` 內補 `super.build(context)`),強制三個分頁的 State 全程留在樹
上,不受 `PageView` 捲動快取影響。這是這類「TabBarView 吃狀態」的標準
Flutter 修法,沒有引入新的狀態管理機制。

無法在此環境用模擬器/實機手動驗證(同上一版 v36 功能的環境限制:
`xcode-select` 未指向 Xcode.app 需要使用者 sudo 密碼、無 Android SDK),三
個問題均以程式碼審查 + widget test 覆蓋驗證,未做手動點按驗證。

## 驗證

`flutter analyze` 乾淨(僅預先存在、跟本次改動無關的 info/warning);
`flutter test` 694/694 全過(較上一版 689 個新增 5 個:進階設定彈窗 2 個、
轉帳週期編輯彈窗 3 個)。
