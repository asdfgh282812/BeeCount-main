# 分期付款(Installment)實機試用後的兩個修正

日期:2026-09-03
背景:子專案 1~4(`2026-09-03-installment-tracking-phase{1,2,3,4}.md`)完成後,
使用者在 macOS 桌面 build 實際試用「設為分期」流程,發現兩個問題,這份文件記錄
修正內容。

## 1. 修正:合併帳單子卡建立分期時直接 crash

### 症狀

信用卡帳戶若掛在合併帳單群組下(`Accounts.parentAccountId != null`),用它建立
分期計畫時會拋出未捕捉的 `ArgumentError`(「不能掛靠已合併帳單的子卡,請改選
群組主帳戶」),整個提交動作卡死,使用者只在 console 看到
`Unhandled Exception`,UI 沒有任何提示。

### 根因

子專案 1 的設計文件 §1.4 要求「`accountId` 若指定,不可為已掛靠某群組的子卡,
子卡要透過選群組本身間接涵蓋」,`local_installment_repository.dart` 照字面
實作了這條校驗。但這個假設不成立——`AccountCardPicker`
(`lib/widgets/biz/account_card_picker.dart:116-119`)本來就把
`type == 'account_group'` 的群組主帳戶整個過濾掉,一般交易表單跟分期建立表單
(`InstallmentEditorPage`)共用同一個帳戶選擇器,**子卡是唯一能選的信用卡帳戶,
群組主帳戶在這個 App 裡從來不是可選項**。這條校驗因此會擋掉每一筆合併帳單子卡
的分期建立,不是邊界情況。

對照之下,同樣的「合併帳單群組」概念在借還款功能(debt tracking)裡完全沒有
類似校驗——這條規則是這次移植時對設計文件的字面照搬,沒有先驗證這個帳戶選擇器
的實際行為。

### 修正

- `lib/data/repositories/local/local_installment_repository.dart`:移除
  `parentAccountId != null` 時拋錯的邏輯,子卡跟一般帳戶一樣允許掛靠分期。
- `lib/data/repositories/installment_repository.dart`:更新
  `createInstallmentPlan` 的介面文件註解,說明這條規則為何不成立、為何移除。
- `test/repositories/local/installment_repository_test.dart`:原本
  「accountId 不可為 account_group 的子卡」的測試(斷言拋錯)改成驗證子卡
  可以正常建立分期計畫。

**沒有動的部分**:子專案 4 的 `offsetExistingBalance`(帳單分期沖銷)仍然拒絕
`account.type == 'account_group'`——這是另一條規則(沖銷需要精確的「這張卡目前
應繳多少」,群組帳戶的應繳是多張子卡分攤加總,沖銷分攤演算法這次没有實作,見
phase4 文件),跟這次移除的「子卡不能建立分期」是两回事,不要混淆。

## 2. 修正:「設為分期」跟既有的「進階設定」彈窗是兩個平行入口

### 症狀

交易表單裡新增分期後,同時存在兩組看起來語意重疊的 UI:
1. 原本就有的「進階設定」彈窗(`RecurringRuleAdvancedSheet`),裡面「單次/
   週期/分期」三個 tab,但「分期」tab 從一開始就是灰掉的佔位符,顯示
   「即將推出」。
2. 子專案 1 另外在表單上新增的一個獨立「設為分期」欄位(點下去彈出另一個
   `InstallmentDraftSheet`)。

使用者的觀察完全正確:選了分期後點開原本的「進階設定」,「分期」tab 依然顯示
「即將推出」,好像分期功能沒接上;但表單下面其實已經有一個獨立生效的分期入口。
這是子專案 1 的實作誤讀了設計文件——設計文件 §5.1 說的「進階區塊」對標 Moze
「單次/週期/分期」三選一,**指的就是這個既有彈窗本身**,不是要在旁邊另開一個
新入口。

### 修正

把分期欄位收集 UI 整個併進 `RecurringRuleAdvancedSheet`:

- `lib/widgets/biz/recurring_rule_advanced_sheet.dart`:
  - `_Mode` enum 新增 `installment`,「分期」tab 從灰色佔位變成可點擊(只在
    `installmentAvailable=true` 時顯示這個 tab,對齐設計文件「僅 expense
    交易可選」——不是灰掉常駐顯示「即將推出」,不適用時直接不出現這個選項)。
  - 選「分期」後顯示的欄位(期數/還款方式/年利率/進階區塊裡的計息週期/寬限期/
    取整開關/餘數位置)直接搬自原本 `InstallmentDraftSheet` 的欄位定義跟校驗
    規則,像素級一致,只是換了個容器。
  - `show()` 回傳型別從 `RecurringRuleDraft?` 改成新的
    `AdvancedScheduleResult`(`{RecurringRuleDraft? recurring, InstallmentDraft?
    installment}` record)——`null` 代表「單次」或取消,`recurring`/
    `installment` 恰有一個非 null 代表對應選擇,呼叫端不用再處理兩個獨立的
    彈窗回傳。
  - 順手把 `_InstallmentDraftSheetBody._confirm()` 原本用 `SnackBar` 顯示校驗
    錯誤的寫法改成 `showToast`(對齐本專案「一律用 showToast,不要用
    SnackBar」的既有慣例——這條原本就該遵守,子專案 1 漏掉了)。
- `lib/widgets/biz/installment_draft_sheet.dart`:砍掉不再使用的
  `InstallmentDraftSheet`/`_InstallmentDraftSheetBody`/`_MethodSelector`/
  `_SegmentedRow`,只留 `InstallmentDraft` 資料模型(`RecurringRuleAdvancedSheet`
  跟 `transaction_entry_form.dart` 都還需要這個型別)。
- `lib/widgets/biz/transaction_entry_form.dart`:刪掉獨立的
  `_buildInstallmentRow`/`_openInstallmentSheet`,`_buildRecurringRow`/
  `_openRecurringSheet` 擴充成單一入口——標籤依「分期草稿 > 週期草稿 > 單次」
  的優先序顯示摘要文字,點下去開同一個彈窗,新增 `installmentAvailable:
  widget.editingTransactionId == null && widget.kind == 'expense'` 傳給彈窗。
  順手修正 `_startSplitMode` 裡「拆帳跟分期衝突」的提示訊息原本誤用了
  `txInstallmentRecurringConflict`(週期衝突文案)而不是
  `txInstallmentSplitConflict`(拆帳衝突文案)的既有小 bug。
- `lib/widgets/biz/installment_action_sheets.dart`:更新一處指向舊
  `InstallmentDraftSheet` 的註解,改指向新的欄位收集位置。
- `test/widgets/recurring_rule_advanced_sheet_test.dart`:既有測試改用新的
  `AdvancedScheduleResult` 型別解包(`.recurring`),新增兩個測試——
  `installmentAvailable=false` 時「分期」tab 不出現、`installmentAvailable=true`
  時可以切到「分期」tab 並確定送出。

### 沒有動的部分

- 分期建立表單(`InstallmentEditorPage`,從帳戶頁分期入口/子專案 4「轉為分期」
  按鈕進入)沒有這個問題——它本來就是獨立的整頁表單,不會跟交易表單的「進階
  設定」彈窗混淆,不在這次修正範圍。
- 遺留了一個沒有清掉的 l10n key:`installmentSetAsInstallmentLabel`(原本
  獨立「設為分期」欄位的預設標籤文案)現在沒有程式碼引用,留在
  `app_en.arb`/`app_zh_TW.arb` 裡未刪除——只是沒用到,不影響行為,之後有機會
  一併清理 l10n 時再刪。

## 驗證

- `flutter analyze`:0 error(跟改動前一致)。
- `flutter test`:全專案 1057 個測試全過(比修正前的 1055 個多兩個,來自
  `recurring_rule_advanced_sheet_test.dart` 新增的「分期 tab 顯示與否」
  兩個測試)。
