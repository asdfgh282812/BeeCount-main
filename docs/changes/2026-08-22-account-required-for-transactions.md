# 交易必須選擇帳戶

日期:2026-08-22
背景:延續 `docs/changes/2026-08-21-debt-tracking.md`、
`docs/changes/2026-08-22-debt-entry-tab-and-account-linkage.md` 這條線——使用者
同時要求全 app 交易一律必填帳戶。完整設計理由見
`docs/superpowers/specs/2026-08-21-debt-entry-and-account-required-design.md`
§B,這裡不重複,只記錄實際落地的變更與實作階段才發現的落差。實作計畫:
`docs/superpowers/plans/2026-08-22-account-required-for-transactions.md`(16 個
task,實際又多跑了 2 個計畫之外的 fix-up commit,見下文各節)。

## 1. 帳戶選擇器移除「不選擇帳戶」(commits `d347ef5`、`c1eb1ee`)

**改了什麼**:`lib/widgets/biz/account_card_picker.dart` 移除 `allowNull` 參數
與 `_buildNoneRow`;`lib/widgets/biz/account_selector.dart` 移除「不選擇帳戶」
chip(`AppLocalizations.accountNone` 分支)。

**關鍵發現(對齐 spec §B.1 的調查結果)**:`AccountCardPicker` 有 5 個呼叫點,
其中 4 個(`recurring_rule_editor_page.dart`、`credit_card_group_payment_page.dart`、
`card_reward_rule_editor_page.dart`、`transfer_form.dart`)**已經**傳
`allowNull: false`——真正依賴預設值 `true` 的只有 `transaction_entry_form.dart`
這一個呼叫點。所以這次改動絕大部分是刪死代碼(拿掉一個實際上到處都已經是
`false` 的參數),唯一有真實行為變化的呼叫點是主要的支出/收入表單。
`AccountSelector` 的「無帳戶」chip 同樣只有一個呼叫點
(`debt_repayment_page.dart`,還款頁本來就已經要求必填帳戶),移除同樣安全。

`test/widgets/account_card_picker_test.dart` 裡驗證「不選擇帳戶」行為的測試
被整段刪除,其餘 3 個測試(幣種過濾、`account_group` 排除、取消回傳 null)
維持不動。

## 2. `TransactionEntryForm._submit()` 擋下無帳戶送出(commit `3adfbab`)

**改了什麼**:在 `_submit()` 的分類/金額檢查之後、`setState` 標記送出中之前,
新增 `_selectedAccountId == null` 時 `showToast` 並 `return`,不呼叫
`repo.addTransaction`。新增 l10n key `txAccountRequiredHint`。

**測試 fallout(重要,對未來動這個表單的人是個坑)**:
`test/widgets/transaction_entry_form_test.dart` 的 `host()` 測試輔助函式只
建了 ledger + category,**完全不建帳戶**——這對這次新增的
`'沒有帳戶時送出被擋下'` 測試剛好是對的 fixture(零帳戶才能讓
`_selectedAccountId` 保持 null),但這個 harness 同時也是檔案裡**既有**第一個
測試(`'選類別+輸入金額+送出'`)在用的同一個 `host()`——新加的必填帳戶檢查
會把這個舊測試一併擋下。修法是在該測試開頭補上:

```dart
final accountId = await repo.createAccount(
  ledgerId: 0, name: 'Cash', type: 'cash', currency: 'CNY', initialBalance: 0,
);
final prefs = await SharedPreferences.getInstance();
await prefs.setInt('default_expense_account_id', accountId);
```

讓 `_loadDefaultAccount()` 在 `pumpWidget` 時自動選上這個帳戶。這個修法在同一
commit(`3adfbab`)裡完成。但同樣的坑在**另一個檔案**裡漏網——
`test/widgets/transaction_split_entry_form_test.dart`(拆帳表單測試,跟
`transaction_entry_form.dart` 共用同一套帳戶必填 `_submit()` 邏輯)當時沒被
同步修正,直到 Task 16 全量回歸測試才暴露出來,另開 fix-up commit `8bd5e0e`
補上完全一樣的「建帳戶 + 寫 `default_expense_account_id`」模式。**教訓**:凡
是任何測試檔案 pump 了 `TransactionEntryForm`/共用其 `_submit()` 邏輯的表單,
且 fixture 裡 ledger 零帳戶,都需要這個修法,不能只改看起來「最相關」的那個
測試檔案。

## 3. `needsAccountAssignment` schema + repository 管線(commits `f5cfdc9`、`bffc516`)

**改了什麼**:`lib/data/db.dart` 的 `Transactions` 表新增
`BoolColumn needsAccountAssignment`(`withDefault(false)`),`schemaVersion`
39 → 40,新增對應的 `ALTER TABLE ... ADD COLUMN` migration(用既有的
`_addColumnIfMissing` helper,冪等)。`transaction_repository.dart` /
`local_transaction_repository.dart` / `local_repository.dart` 三層新增:
`addTransaction` 的 `needsAccountAssignment` 參數(預設 `false`)、
`getTransactionsNeedingAccountAssignment(ledgerId)` 查詢(供「待確認帳戶」
列表用)、`setTransactionAccountAssignment({id, accountId})` 補選帳戶並清除
旗標的 setter(對齐既有 `setTransactionDebtLink` 的 change-tracking 慣例)。

**關鍵坑(對未來加欄位的人是個一般性教訓)**:`Transaction` 這個 Drift
生成的資料類多了一個欄位後,任何**手動用 positional/named 建構子
`Transaction(...)` 出物件、而不是走 `TransactionsCompanion.insert(...)`
這條 insert 路徑**的地方都會編譯失敗或漏欄位。這次真正命中的檔案分兩批:

- 跟 schema 改動同一個 commit(`f5cfdc9`)裡順手修掉的:
  - `lib/data/repositories/local/local_tag_repository.dart`(手寫 raw SQL 查
    詢後手動把每一 row map 回 `Transaction`)
  - `lib/pages/settings/widget_management_page.dart`(`_sampleTransaction()`
    測試/預覽用的假資料建構器)
  - `test/data/sync_pull_errors_schema_test.dart`
- Task 16 全量 `flutter analyze`/`flutter test` 才挖出來、另開 fix-up commit
  `2c6e441` 補的(全部只是幫 `Transaction(...)` 呼叫補一個
  `needsAccountAssignment: false`,不改邏輯):
  - `test/sync/transaction_multi_currency_apply_test.dart`
  - `test/widget/dashboard_view_test.dart`
  - `test/widget/recent_view_test.dart`
  - `test/widget/widget_preview_generator_test.dart`
  - `test/widget/widget_render_harness_repro_test.dart`

**一般性教訓**:替 Drift 表加任何一個新的非 nullable/有預設值欄位時,光改
schema + 補一個「最明顯」的 repository 測試是不夠的,必須額外
`grep -rn "Transaction("`(以及未來其他表被加欄位時的同名資料類建構子)找出
所有手動建構呼叫點——這次漏網的 5 個檔案全部是測試檔案,靠 Task 16 的
`flutter analyze`/`flutter test` 全量回歸才兜住,不是靠當初的計畫文字預先
列出來的。

## 4. AI 記帳攔截:`resolveMissingAccount` / `MissingAccountSkipped` / `skippedForMissingAccountCount`(commits `9a9e249`、`4c44a71`、`4464d15`、`88ec39f`、`60c0e28`、`536a8fb`)

**改了什麼**:`lib/services/billing/bill_creation_service.dart` 新增
`typedef ResolveMissingAccount = Future<int?> Function(BillInfo bill)` 與
`class MissingAccountSkipped implements Exception`。`createFromBill` 找不到
帳戶(`_matchAccount`/`_matchAccountByName`/`_getDefaultAccountId` 都失敗)且
`transactionType != 'transfer'` 時:
- 有 `resolveMissingAccount` callback → 呼叫它;回傳有效 id 就用該 id 建立
  交易;回傳 `null`(使用者取消)→ 拋 `MissingAccountSkipped`,**不建立交易**。
- 沒有 callback → 交易照常建立(`accountId = null`),但
  `needsAccountAssignment = true`(見第 5 節)。

`BookkeepingResult` 新增 `skippedForMissingAccountCount` 欄位。
`AiBookkeeper.fromText/fromImage/fromAudio` 都新增
`resolveMissingAccount` 參數並轉發進 `_persistAll`;`_persistAll` 的
per-bill 迴圈 `catch` 塊區分 `MissingAccountSkipped`(計入 `skipped`,不算
`failed`)跟其他例外(計入 `failed`)。

**為什麼要把「使用者取消」跟「真正失敗」分開計數**:取消是使用者主動決定
「這筆先不記」,是預期內的正常路徑,不代表資料寫入或 AI 解析出錯;混進
`failedCount` 會讓「AI 記帳偶爾失敗」跟「使用者取消了幾筆」這兩個完全不同
嚴重程度的訊號混在一起,結果摘要也沒法分別告知使用者。

**三個前台入口的實作**(對話 `ai_chat_service.dart`/`ai_chat_page.dart`、照片
`image_billing_helper.dart`、語音 `voice_billing_helper.dart`)都是同一個模式:
把 `resolveMissingAccount` 實作成 `(bill) async { 跳 AccountCardPicker.show(...)；
回傳 picked?.accountId; }`,並在成功 toast/訊息裡用新增的
`aiBillingAccountSkippedHint(count)` l10n key 追加「已略過 N 筆(未選帳戶)」
提示(跟既有的 `aiBillingRateMissingHint` 多幣種降級提示並列在同一個
`note`/`toastText` 裡,用 `whereType<String>().join('\n')` 拼接)。這個
callback 設計本身只是一個純函式型別參數,`lib/ai/`、`lib/services/ai/`、
`lib/services/billing/` 不因此新增任何 UI/Flutter widget 依賴,維持既有的
L1 → L2 → L3 單向分層(`lib/ai/README.md`)。

## 5. 背景/非互動路徑的 `needsAccountAssignment` 旗標 + 待確認帳戶列表(commits `249606d`、`142b236`、`8ffd669`、`ed34889`、`2c6e441`)

**改了什麼**:三個完全沒有 UI 可攔截使用者的路徑,找不到帳戶時改成「照常
建立但標旗標」,而不是靜靜留空:

- **週期性交易產生**(`local_repository.dart::_createOccurrenceTransaction`,
  `249606d`,只改了 1 行):`addTransaction(...)` 呼叫加
  `needsAccountAssignment: rule.type != 'transfer' && accountId == null`。
  轉帳規則排除,因為轉帳有自己的 from/to 帳戶語意,且沒有
  `fromAccountId` 的轉帳規則本來就在更早的 guard 被跳過,不會走到這個方法。
  這條路徑目前只有 Task 3 上線前建立的舊規則才可能命中——新規則已經在建立
  時就被表單的必填帳戶驗證擋下。
- **CSV 匯入**(`data_import_service.dart`,`142b236`,只加了 4 行):只在
  「CSV 該列**有**填帳戶名稱、但對應不到現有帳戶」時標記
  (`tx.type != 'transfer' && tx.accountName != null && accountId == null`)。
  刻意跟「CSV 該列本來就沒有帳戶欄位值」區分開——後者維持現狀直接留空,
  因為使用者根本沒給過帳戶名稱,沒有「待確認」的東西可以補選。
- **背景自動記帳的無回調兜底**:`BillCreationService.createFromBill` 沒收到
  `resolveMissingAccount` 時直接落到 `needsAccountAssignment = true`(第 4
  節已述,`auto_billing_service.dart` 的螢幕截圖監聽/通知文字監聽都是透過
  `AiBookkeeper` 沒帶 callback 走到這裡)。

**「待確認帳戶」列表(`8ffd669`)**:新增 `pending_account_providers.dart`
(`pendingAccountRefreshProvider` 手動刷新計數器 + `FutureProvider.family`
查詢)、`pages/account/pending_account_transactions_page.dart`(列出
`needsAccountAssignment = true` 的交易,逐筆點擊跳 `AccountCardPicker`,
選完呼叫 `setTransactionAccountAssignment` 並觸發刷新),`accounts_page.dart`
在既有 `_DebtEntryCard` 旁加一張只在有待確認項目時渲染的入口卡片。

**通知深連結(`ed34889`)**:`auto_billing_service.dart` 的
`_showNotification`/`_showFinalNotification` 新增可選 `payload` 參數;截圖/
通知文字兩條成功路徑在推播前先查一次
`getTransactionsNeedingAccountAssignment(ledgerId)`,非空時把通知文案換成
「點擊選擇這筆交易的帳戶」並帶上 `payload: 'pending_account'`。
`_notificationsPlugin.initialize` 註冊 `onDidReceiveNotificationResponse`,
點擊時若 `payload == 'pending_account'` 就用 `globalNavigatorKey` push
`PendingAccountTransactionsPage`。

**`globalNavigatorKey` 搬家(`ed34889`)**:這個 key 原本定義在 `main.dart`
裡。`auto_billing_service.dart` 要用它跳轉,但直接 `import '../../main.dart'`
會造成 import 循環——實際的環是:`main.dart` import
`services/platform/*.dart`(啟動時初始化背景監聽服務)→ 這些檔案 import
`services/automation/auto_billing_service.dart` → 若後者又 import
`main.dart` 拿 `globalNavigatorKey`,就繞回 `main.dart` 形成循環 import。
解法是把 `globalNavigatorKey` 抽成獨立的
`lib/utils/global_navigator_key.dart`,`main.dart` 跟
`auto_billing_service.dart` 都改成 import 這個新檔案,打破循環。這個 key
原本的用途(`BeeCount Cloud` 登入 `requires_2fa` 時彈 `Login2FAChallengeView`)
不受影響。

`needsAccountAssignment = true` 且 `accountId = null` 的交易,在帳戶餘額計算
上跟現有「null 帳戶」的行為完全一樣(本來就不計入任何帳戶餘額)——這個旗標
純粹是提醒 UX 用,不改變既有帳戶餘額/報表計算邏輯。

## 6. 刻意不做的事(對齐 spec §B.4)

- **不對 `Transactions.accountId`/`toAccountId` 做 non-null schema migration
  或歷史資料 backfill**。這兩欄在 schema 層維持 nullable;「交易必須有帳戶」
  這個規則完全在應用層落實(表單驗證擋送出 / AI 路徑攔截選擇 / 背景路徑標
  `needsAccountAssignment` 事後補選三種機制,依當下有多少 UI 可用分流),不
  在資料庫層強制。這個決定的取捨是:既有資料庫裡任何歷史上留空的
  `accountId`/`toAccountId`(這次改動之前就存在的)不會被這次改動觸碰或報錯,
  換來的代價是「帳戶必填」不是資料庫能保證的不變量,完全依賴應用層每一條
  寫入路徑都正確走過對應的檢查/攔截/標記機制——這正是第 3 節「漏了手動
  `Transaction(...)` 建構點」跟第 2 節「漏了一個測試 fixture」這兩個 fix-up
  commit 會發生的根本原因:規則沒有資料庫層的保底,只能靠每個寫入點各自
  自覺遵守。

## 測試

- `test/widgets/account_card_picker_test.dart`:刪掉「不選擇帳戶」測試,保留
  其餘 3 個。
- `test/widgets/transaction_entry_form_test.dart`:既有第一個測試補帳戶
  fixture;新增「沒有帳戶時送出被擋下」測試。
- `test/widgets/transaction_split_entry_form_test.dart`:fix-up commit
  `8bd5e0e` 補帳戶 fixture。
- `test/repositories/local/needs_account_assignment_test.dart`:新增,驗證
  `addTransaction(needsAccountAssignment: true)` 可查詢、補選帳戶後可查詢
  結果消失且旗標清除。
- `test/services/billing/bill_creation_service_test.dart`:新增
  `resolveMissingAccount` group(無回調標旗標 / 有回調給 id / 有回調取消拋
  `MissingAccountSkipped`)。
- `test/services/ai/ai_bookkeeper_test.dart`:新增
  `resolveMissingAccount` 相關測試(取消 → `skippedForMissingAccountCount`
  計數;給 id → 正常建立並掛帳戶)。
- fix-up commit `2c6e441`:5 個既有測試檔案的手動 `Transaction(...)`
  建構呼叫補 `needsAccountAssignment: false`(見第 3 節)。
