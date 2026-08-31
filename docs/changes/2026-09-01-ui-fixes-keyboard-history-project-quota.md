# UI 修正:伺服器位址輸入頁鍵盤遮擋、歷史備註排除系統備註、鍵盤上方建議條、專案剩餘額度

日期:2026-09-01

背景:使用者回報四個 UI 小問題(附截圖,部分為 moze 的畫面當設計參考)。

## 1. 伺服器位址輸入頁被鍵盤擋住

**改了什麼**:[lib/pages/auth/welcome_page.dart](lib/pages/auth/welcome_page.dart)
`_buildServerAddressPage` 的最外層從 `Padding` 換成 `SingleChildScrollView`。

**為什麼**:這一頁的 `Column` 用 `mainAxisAlignment: MainAxisAlignment.center`
+ 固定高度的圖示/文字/輸入框/按鈕,鍵盤打開時可用高度縮水,固定內容在縮水後
的空間裡溢出,把輸入框跟送出按鈕擠出可視範圍——同一份檔案裡的
`_buildWelcomePage`/`_buildCurrencyPage` 早就用 `SingleChildScrollView`
包過完全一樣的結構(見該檔案 `_buildWelcomePage`),伺服器位址頁當初漏了
這一層。改成 `SingleChildScrollView` 後鍵盤打開時可以捲動看到完整內容,
不需要額外邏輯。

## 2. 歷史備註排除系統自動產生的備註

**改了什麼**:
- [lib/models/note_history.dart](lib/models/note_history.dart) 新增
  `kSystemGeneratedNotePrefixes` 常數(目前兩個前綴:`信用卡回饋入帳`、
  `信用卡繳款(帳單`)。
- [lib/data/repositories/local/local_transaction_repository.dart](lib/data/repositories/local/local_transaction_repository.dart)
  `getNoteHistory` 的 SQL `WHERE` 子句動態加上對應的 `NOT LIKE` 條件。

**為什麼**:信用卡回饋入帳的備註由 BeeCount Cloud 端結算時寫入(見該倉庫
`src/services/card_reward_payout.py`/`src/routers/write/card_reward_rules.py`
的 `信用卡回饋入帳：`/`信用卡回饋入帳（手動）：` 開頭),信用卡繳款備註由
本機 `creditCardPaymentNote()`(`lib/utils/credit_card_payment.dart`)產生
——這兩種備註使用者從沒有「自己打過」,只是剛好觸發了會寫這種備註的自動
流程,不該混進「歷史備註」清單裡佔位置。用固定前綴 `NOT LIKE` 過濾,不影響
既有 `getMerchantHistory`(商家欄位不會被這兩種自動流程寫入,不需要同樣的
排除)。

**測試**:新增 [test/repositories/note_history_test.dart](test/repositories/note_history_test.dart)
驗證兩種系統備註都被排除、使用者自己輸入的備註不受影響。

## 3. 歷史備註/歷史商家改成鍵盤上方建議條(比照 moze)

**改了什麼**:
- 新檔 [lib/widgets/biz/keyboard_suggestion_bar.dart](lib/widgets/biz/keyboard_suggestion_bar.dart)
  (`KeyboardSuggestionBar`)——一個純展示用的水平 chip 列,不顯示使用次數
  數字。呼叫端只要把它當作表單 `Column` 裡、系統鍵盤前的最後一個子元件
  (欄位聚焦、鍵盤打開時才 render),就會自然貼齊鍵盤上緣,不需要另外用
  `Stack`/`MediaQuery` 手動算位置——[lib/widgets/biz/transaction_entry_form.dart](lib/widgets/biz/transaction_entry_form.dart)
  原本「小算盤」(`AmountCalculatorKeypad`)就是用同一個技巧貼齊鍵盤位置,
  直接沿用。
- `transaction_entry_form.dart`:名稱欄位(`_nameFocus`)/商家欄位
  (`_merchantFocus`)聚焦、且對應的 `_frequentNotes`/`_frequentMerchants`
  非空時,顯示 `KeyboardSuggestionBar`;點 chip 呼叫新增的
  `_applyNoteSuggestion`/`_applyMerchantSuggestion`——只填入文字、不呼叫
  `unfocus()`,鍵盤保留開啟(跟使用者確認過的行為,選完可能還要接著手動
  微調文字)。
- 移除舊版「點時鐘圖示彈出 `AlertDialog`,清單有使用次數紅色徽章」的做法
  ——整個換掉,不保留當備案(跟使用者確認過)。刪除
  [lib/widgets/biz/note_picker_dialog.dart](lib/widgets/biz/note_picker_dialog.dart)/
  [lib/widgets/biz/merchant_picker_dialog.dart](lib/widgets/biz/merchant_picker_dialog.dart)
  ——確認過這兩個類別除了自己的檔案外只有 `transaction_entry_form.dart`
  這一處引用,整個刪掉不留 dead code。連帶移除只被
  `MerchantPickerDialog` 標題用到、變成 dead 的 l10n key
  `appearanceMerchantHistory`(`appearanceNoteHistory` 仍保留,設定頁的
  「顯示範圍/排序/上限」區塊標題還在用)。
- `transaction_entry_form.dart` 的名稱/商家 `TextField` 加上
  `Key('nameField')`/`Key('merchantField')`,方便 widget test 直接鎖定
  (比照既有 `Key('amountDisplayTap')` 的慣例)。

**為什麼**:使用者提供 moze 的截圖當參考,要的是「聚焦欄位就直接在鍵盤
上方看到建議,不用另外點、不用看到使用次數這種雜訊數字」——跟現有的
`NoteHistoryScope`/`NoteHistorySort`/`limit` 這組使用者可調設定(設定頁裡)
完全正交,沒有動到,只是把「呈現方式」從彈窗換成鍵盤上方建議條。

**測試**:[test/widgets/transaction_entry_form_test.dart](test/widgets/transaction_entry_form_test.dart)
新增一個 case:聚焦名稱欄位時建議條出現、點 chip 後文字填入且欄位仍保有
焦點。

## 4. 記帳表單「選擇專案」顯示剩餘額度

**改了什麼**:[lib/widgets/biz/project_picker.dart](lib/widgets/biz/project_picker.dart)
`_ProjectPickerSheet` 原本只呼叫 `getAllProjects` 拿純清單,改成呼叫
`getAllProjectUsages(ledgerId, DateTime.now())` 拿 `List<ProjectWithUsage>`
(跟 `ProjectOverviewPage` 用同一個 repository 方法)。`_ProjectRow` 新增
`quotaText`/`quotaColor` 兩個可選欄位:有預算的專案顯示
`${l10n.budgetRemaining} ${currencySymbol}${remaining}`(剩餘為負時紅字,
否則綠字,跟 `ProjectOverviewPage` 卡片的既有配色慣例一致),純記錄專案
顯示 `l10n.projectCardPureTracking`(「純記錄」)。「不指定專案」那一列
沒有額度概念,`quotaText` 留空。

**為什麼**:使用者提供的 moze 專案清單截圖裡,每一列除了名稱還有額度/
金額,現有的 `ProjectPicker`(記帳表單裡「不指定專案」欄位點開的
bottom sheet)只有圖示+名稱+打勾,看不出這個專案還剩多少可花——跟使用者
確認過,要改的是這個 bottom sheet,不是已經有完整預算卡片的
`ProjectOverviewPage`(那邊本來就有進度條+已用/剩餘金額)。文案刻意沿用
`ProjectOverviewPage` 既有的 `budgetRemaining`/`projectCardPureTracking`
措辭,不重新發明一套跟 moze 一模一樣但跟 app 其他地方不一致的文字。

**測試**:新增 [test/widgets/project_picker_test.dart](test/widgets/project_picker_test.dart)
驗證有預算專案顯示剩餘額度、純記錄專案顯示「純記錄」、點列仍正確回傳
`ProjectPickResult`。撰寫時發現 `ProjectPicker`/`TransactionEntryForm` 的
widget test 如果不 override `currentLedgerProvider`(讓它繼續用真正的
drift `watchLedger` stream),`pumpAndSettle` 會真的卡住而不是丟例外
timeout——`test/widgets/transaction_entry_form_test.dart` 既有的 `host()`
早就用 `currentLedgerProvider.overrideWith((ref) => Stream.value(...))`
繞開這個問題,`project_picker_test.dart` 照抄同一個做法。

## 未做的事

- l10n:本次新增/異動的字串只寫進 `app_en.arb`/`app_zh_TW.arb`(專案目前
  政策,不再維護 `app_zh.arb`/`app_ko.arb`),`flutter gen-l10n` 照常會讓
  這兩個未維護語系顯示「未翻譯」,是預期行為。
- 沒有調整 `getRecentDistinctAmounts`(常用金額)——使用者這次只提到備註/
  商家的歷史清單,金額的常用列沒有被回報有系統自動產生的雜訊,不在範圍內。

全專案 `flutter test`(963 個測試)、`flutter analyze` 均通過。UI 互動
(鍵盤上方建議條的貼齊效果、專案 bottom sheet 的顯示)未能在真機/模擬器上
實際點過(受限於本機 iOS 模擬器工具鏈問題,同
`docs/changes/2026-09-01-suggested-tab-smart-defaults-pull-to-submit.md`
記錄的既有限制),僅透過 widget test 驗證邏輯行為,建議下次真機測試時
一併確認。
