# 欠款入口改版（記帳表單第4分頁）+ 帳戶連動

日期:2026-08-22
背景:延續 `docs/changes/2026-08-21-debt-tracking.md` 的借還款初版——當時
新增欠款只有 `accounts_page.dart` 的 `_DebtEntryCard` → `DebtListPage` →
`DebtEditorPage` 這一條路,且 `DebtEditorPage` 沒有帳戶欄位,新增欠款不會
連動任何帳戶餘額,要等使用者事後另外去「還款」頁補記一筆才會動到帳戶。
完整設計理由見 `docs/superpowers/specs/2026-08-21-debt-entry-and-account-required-design.md`
§A,這裡不重複,只記錄實際落地的變更。

## 1. `createDebtWithOriginTransaction`(commit `2983a18`)

**改了什麼**:`DebtRepository` 新增方法
`createDebtWithOriginTransaction({ledgerId, direction, counterpartyName,
principalAmount, accountId, dueAt, note})`,`LocalRepository` 實作:包在
一個 `db.transaction()` 裡依序呼叫既有的 `addTransaction`(payable →
income、receivable → expense,金額 = 本金,立即改動 `accountId` 對應帳戶
餘額)與 `createDebt`,回傳新建 Debt 的本地 id。

**為什麼要新方法而不是分兩步呼叫**:兩個呼叫端(見下)都需要「建交易 +
建欠款」同時成功或同時失敗——分兩步呼叫沒有 transaction 包裹的話,交易建
成功但欠款建失敗(或反過來)會留下無法對應的半殘資料。`addTransaction`/
`createDebt` 各自已經做好自己的 change-tracker 記錄
(`recordLedgerChange`),兩者都是 ledger-scoped 寫入,包在同一個 db
transaction 裡不需要新增任何 sync 相關程式碼。

**關鍵設計決策(對齐 spec §A.2)**:這筆起點交易**刻意不寫入
`debtSyncId`**,不透過既有的 `setTransactionDebtLink` 把它跟新欠款連起
來。原因是 BeeCount Cloud 交易表單裡「+ 建立新欠款」的既有做法就是這樣
(`debt_id === '__new__'` sentinel,程式碼註解原文說明:一旦把起點交易的
`debt_id` 指向自己剛建的欠款,`remainingAmount` 的即時運算會把這筆起點交
易當成「還款」倒扣,導致新欠款一建立 remaining 就被沖抵成 0)。本次沒有
修改任何 BeeCount-Cloud repo 的程式碼——只是讀 Cloud 既有實作來對齐行為,
純 App 端變更。

`LocalDebtRepository`(委托模式下 `LocalRepository` 內部使用的另一個
`DebtRepository` 實作類)也補了一個 `createDebtWithOriginTransaction`
override,但直接 `throw UnsupportedError`——這是計畫文字沒有明講、實作時
才發現必須處理的一點:`LocalDebtRepository` 只持有 `db`,沒有
`TransactionRepository`/`addTransaction` 的引用,組不出完整邏輯(幣別折
算、reward rule、change tracking 等)。真正實作只能放在
`LocalRepository`(它能同時呼叫自己身上的 `addTransaction` 與
`createDebt`)。這個 stub 安全,因為 `LocalDebtRepository` 從未被單獨當
成 `DebtRepository` 對外曝露——它只是 `LocalRepository` 內部的私有委托對
象,所有外部呼叫都經過 `LocalRepository` 這一層,不會走到
`LocalDebtRepository` 的這個 override。

測試:`test/repositories/local/debt_repository_test.dart` 新增案例驗證
交易與欠款同時建立成功、帳戶餘額確實變動、且新欠款的 `remainingAmount`
沒有被起點交易沖抵。

## 2. 記帳表單第 4 分頁「欠款」(commits `ec3e0cf`、`021fce9`、`08490da`)

**改了什麼**:
- 新增 `lib/widgets/transaction/debt_entry_form.dart`(`DebtEntryForm`,
  `ConsumerStatefulWidget`):欄位由上到下——方向(我欠款/款項應收)、對
  象、本金、帳戶(`AccountSelector`,必填)、到期日、備註。送出時呼叫
  `repo.createDebtWithOriginTransaction`,成功後觸發 `onDebtCreated`
  callback。欄位集合對齐 `DebtEditorPage` 新增模式,唯一差異(此表單本
  來就有)是帳戶欄位。
- `lib/pages/transaction/transaction_editor_page.dart`:`TabController`
  length 從 3 改成 4,`TabBar` 加第 4 個 Tab「欠款」
  (`l10n.debtTabLabel`),`TabBarView` 對應加一個 `DebtEntryForm`,
  `onDebtCreated` 接的行為是「若可以 pop 就 pop 掉這個編輯頁」,跟「支出/
  收入/轉帳」三個分頁送出後的收尾行為一致。
- l10n:`app_en.arb`/`app_zh_TW.arb` 加 `debtTabLabel` key(依既定政策不
  再維護 `app_zh.arb`/`app_ko.arb`——但 `flutter gen-l10n` 仍會為所有既
  有語言重新生成 `app_localizations_*.dart`,所以 `app_localizations_ko.dart`
  也會看到這個 key 的生成程式碼,這不是新增翻譯,只是既有 fallback 機制
  的產物)。

## 3. `DebtEditorPage` 新增模式補帳戶欄位(commit `88f21d0`)

**改了什麼**:`DebtEditorPage` 新增模式(`!_isEditing`)加一個
`SectionCard` 包 `AccountSelector`,必填校驗(空值 toast
`l10n.debtRepaymentAccountRequired`,跟還款頁用同一個文案 key)。送出邏
輯從呼叫 `repo.createDebt(...)` 改成呼叫
`repo.createDebtWithOriginTransaction(...)`,多帶一個 `accountId`。編輯
模式完全不變——不顯示帳戶欄位,也不建立新交易(`principalAmount`/
`direction` 建立後本來就鎖定不可改,帳戶連動只在「新增」當下發生一次)。

## 刻意不做的事(deliberately out of scope,對齐 plan)

- 沒有改 `Debts` 表結構或 schema version——`createDebtWithOriginTransaction`
  純粹組合既有的 `addTransaction`/`createDebt`,不需要新欄位。
- 沒有修改 BeeCount-Cloud 任何程式碼——只讀了 Cloud 的
  `debt_id === '__new__'` 既有實作來對齐行為決策(見上文 §1)。
- `accounts_page.dart` 的 `_DebtEntryCard` 入口卡片維持不變,繼續作為
  「欠款清單」的導覽入口(`DebtListPage`)。
- `DebtRepaymentPage`(記錄還款/收款)完全不受影響——起點交易跟還款交易
  是兩條獨立路徑,起點交易不寫 `debtSyncId` 所以不會出現在
  `DebtListPage` 的還款記錄展開列表(`_RepaymentList`)裡,符合預期。

## 測試

`test/repositories/local/debt_repository_test.dart` 新增
`createDebtWithOriginTransaction` 案例(交易建立、帳戶餘額變動、
remaining 未被自己沖抵)。UI 層(`DebtEntryForm`、`DebtEditorPage` 新欄
位)沒有新增 widget test,靠既有的手動驗證與 repository 層測試把關送出
邏輯的正確性。
