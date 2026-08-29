# 轉帳手續費/折損 + 餘額快速代入

設計文件:[docs/superpowers/specs/2026-08-29-transfer-fee-discount-design.md](../superpowers/specs/2026-08-29-transfer-fee-discount-design.md)。
延續 [2026-08-29-cross-currency-transfers.md](./2026-08-29-cross-currency-transfers.md)(同一支 `transfer_form.dart`,複用/擴充 `toAmount` 的語意)。

跨三個 repo:App 本身(`BeeCount-main`)、`BeeCount-Cloud` 後端、`BeeCount-Cloud` 網頁前端。

## 背景

App 端追平 Web 版已上線一半的手續費/折扣功能——Cloud 的 `read_tx_projection`
表、`fee_amount`/`discount_amount` 欄位、sync merge spec 早就存在,但只放行
`expense`/`income`,`transfer` 型別一律被 `_normalize_fee_discount_amount` 400
拒絕,Web 前端 UI 也在 `tx_type !== 'transfer'` 擋掉。這次三邊一起解除限制,
讓轉帳也能設定「轉出側手續費」+「轉入側折損」,並且兩個帳戶卡片都加上
「代入目前餘額」的一鍵按鈕。

## 一、App(`BeeCount-main`)

### 1. Schema — `Transactions` 新增 4 欄位([lib/data/db.dart](../../lib/data/db.dart))

- `feeAmount`/`feeLabel`/`discountAmount`/`discountLabel`,欄位命名直接對齊
  Cloud 既有的 `fee_amount`/`fee_label`/`discount_amount`/`discount_label`,
  Cloud 端完全不需要新 migration。
- `schemaVersion` 45 → 46,`_addColumnIfMissing` 純加欄位遷移,無需回填——
  舊資料四個欄位皆為 `null`,語意上等同「沒有手續費/折損」。
- `RecurringTransactions` 表不變:周期性轉帳規則不支援手續費/折損,範圍比照
  既有 Web 版「recurring rule 不支援 fee/discount」的既有限制。

### 2. Repository 層 — 新增具名參數貫穿三層

- `lib/data/repositories/transaction_repository.dart`(介面)、
  `lib/data/repositories/local/local_transaction_repository.dart`(子倉實作)、
  `lib/data/repositories/local/local_repository.dart`(聚合層 wrapper——**設計
  文件沒提到但研究時發現的第三層**,`addTransaction`/`updateTransaction` 在
  這裡也各自包了一層轉發,漏改會讓新欄位在聚合層被靜默丟掉)。
- `addTransaction()` 用普通 `double?`/`String?`(insert 沒有「既有值」需要
  保留)。`updateTransaction()` 用 `dynamic`,比照既有 `toAmount` 的 tri-state
  寫法:不傳 = 不動既有值;顯式傳 `d.Value<double?>(null)`/`d.Value<String?>
  (null)` = 清空;傳值 = 更新。

### 3. 餘額計算 — [lib/data/repositories/local/local_account_repository.dart](../../lib/data/repositories/local/local_account_repository.dart)

新增兩個單一權威 helper:

```dart
double _transferOutEffect(Transaction t) => t.amount + (t.feeAmount ?? 0);
double _transferInEffect(Transaction t) =>
    (t.toAmount ?? t.amount) - (t.discountAmount ?? 0);
```

替換了 **7** 處(設計文件列了 6 處,實作時 grep 發現 `getAccountExpense`
也把轉出腳算進「支出」統計,是第 7 處遺漏,一併修正,不然轉出側手續費不會
反映在支出統計上):`getAccountBalance`、`getAccountGlobalBalance`、
`getAccountBalanceInLedger`、`getAccountIncome`、`getAccountExpense`、
`getAccountDailyBalances`(range 前累加 + 逐日累加兩處)。沒有手續費/折損的
舊資料兩個 helper 都退化回原本的 `t.amount`/`t.toAmount ?? t.amount`,行為
完全不變——用 `test/repositories/transfer_fee_discount_balance_test.dart`
(12 組case)驗證回歸 + 各種手續費/折損組合(含跨幣別 + 折損疊加、金額為 0
邊界情況)。

### 4. 轉帳表單 UI — [lib/widgets/transaction/transfer_form.dart](../../lib/widgets/transaction/transfer_form.dart)

- **代入餘額**:`_AccountCardSlot` 的餘額文字旁加一個向下箭頭(`Tooltip` +
  `GestureDetector`),餘額非零才顯示。轉出側點擊呼叫 `_fillFromBalance()`
  填進計算機式金額(`_amountStr`);轉入側點擊呼叫 `_fillToBalance()` 填進
  `_toAmountCtrl` 並設 `_toAmountManuallySet = true`。
- **`_buildCrossCurrencySection` 放寬顯示條件**:原本只在跨幣別
  (`fromCurrency != toCurrency`)時顯示,現在改成三選一:跨幣別 **或**
  `_discountEnabled == true` **或** `_toAmountManuallySet == true`(沿用既有
  flag,不加第三個 bool)。同幣別但因後兩個新理由顯示時,「採用線上匯率」
  開關/匯率展示列沒有意義,一併隱藏;預設轉入金額 = 轉出金額(無匯率換算)。
- **手續費/折損面板**:新增 `_feeEnabled`/`_discountEnabled` 兩個 bool +
  4 個 controller/focusNode。轉出金額列旁的「+」(`_buildAdjustmentToggleButton`)
  展開手續費面板(`feeAmount`/`feeLabel`,轉出帳戶幣別);轉入金額區塊裡的
  另一個「+」展開折損面板(`discountAmount`/`discountLabel`,轉入帳戶幣別)。
  兩者完全獨立,互不影響。
- **驗證**(`_submit()`):`feeAmount`/`discountAmount` 皆須 ≥ 0;
  `discountAmount` 不能讓實際轉入金額變負數(`discountAmount <=
  resolvedToAmount ?? total.abs()`)。新增 l10n key
  `transferDiscountExceedsAmountError`/`transferAdjustmentNegativeError`/
  `transferFillBalanceTooltip`/`transferFeeLabelHint`/`transferAddFeeButton`/
  `transferAddDiscountButton`/`transferRemoveAdjustmentButton`/
  `transferAmountLabel`(僅 `app_en.arb`/`app_zh_TW.arb`,依既有 l10n 政策
  不維護 `app_zh.arb`/`app_ko.arb`)。
- `TransferForm` 新增 `initialFeeAmount`/`initialFeeLabel`/
  `initialDiscountAmount`/`initialDiscountLabel` 參數,編輯既有轉帳時回填。
  串接路徑同 `initialToAmount`:`TransactionEditorPage` →
  `TransactionEditUtils.editTransaction`/`copyTransaction` → `ai_chat_page.dart`
  的編輯入口比照補上。

### 5. 同步序列化/解析

- `lib/cloud/sync/entity_serializer.dart`:`serializeTransaction` 新增 4 行
  「有值才發」寫法(同 `toAmount`),wire key 直接對齊 Cloud 既有 merge spec。
- `lib/cloud/sync/sync_engine_apply.dart`:這 4 個欄位是獨立絕對數值(不像
  `toAmount` 由匯率衍生),用跟 `debtSyncId`/`projectSyncId` 同款的「缺鍵不
  覆蓋」簡單寫法,不需要比照 `toAmount` 的等比例重算(rescale)邏輯。

## 二、BeeCount-Cloud 後端

不需要新 migration——`read_tx_projection` 已有這組欄位,merge spec 也已
存在,只是解除 tx_type 限制。

- `src/routers/write/_shared.py::_normalize_fee_discount_amount()`:新增
  `transfer` 分支——只驗證 `fee_amount`/`discount_amount`(若有帶)皆 ≥ 0,
  **不**重算 `amount`(維持客戶端算好的「本體」語意),`base_amount` 對
  transfer 不使用、一律落 `None`(即使 payload 帶了值也丟棄不報錯)。硬擋條件
  從 `{"expense","income"}` 放寬成 `{"expense","income","transfer"}`。
- `src/routers/read/workspace.py`:餘額 + 淨值計算兩處都疊加手續費/折損,
  公式跟 App 端 `_transferOutEffect`/`_transferInEffect` 對齊——
  - SQL 聚合(`transfer_from`/`transfer_to`):`amt` 改成
    `SUM(amount + COALESCE(fee_amount,0))`/
    `SUM(COALESCE(to_amount,amount) - COALESCE(discount_amount,0))`。
  - `getNetWorthHistorySeries` 用的 `_apply()` 函式:新增 `fee_amt`/
    `discount_amt` 兩個參數,`bal[fa] -= amt + fee_amt`、
    `bal[ta] += to_amt - discount_amt`;對應的 `select(...)` 查詢欄位也補上
    `fee_amount`/`discount_amount`。
- `src/projection.py`:欄位既有的 read/write 映射本來就泛用(不分
  tx_type),驗證過對 transfer 型別的列也能正確讀寫,不需要改。

## 三、BeeCount-Cloud 網頁前端

- `forms.ts`:`TxForm.fee_enabled` 文件註解更新(expense/income 共用面板 vs
  transfer 獨立兩個面板);新增 `discount_enabled: boolean`,只給 transfer 用。
- `TransactionsPanel.tsx`:
  - 轉出金額列旁的「+」(`fee_enabled`)guard 從「只在 expense/income 顯示」
    改成一律顯示;面板內的折扣輸入列只在非 transfer 時渲染(transfer 折損
    是獨立面板)。
  - 轉入金額區塊(新增,`isTransfer` 時渲染):「+」(`discount_enabled`)
    展開折損面板;同幣別 + 折損開啟時顯示唯讀的「轉出金額 − 折損」預覽;
    跨幣別時沿用既有 `FxRateRow` 換算列,折損疊加顯示在上面,不重複一個
    換算列。
  - `applyTxType()`:切到 transfer 或從 transfer 切回時,清空的是「跨型別
    語意不同」的 fee/discount/discount_enabled 4+1 個欄位——不是因為
    transfer 不能用這些欄位(現在可以用了),純粹避免 expense/income 填過
    的舊值誤帶進 transfer 的手續費/折損面板,反之亦然。
  - **代入餘額**:from/to 帳戶選擇按鈕旁加一鍵按鈕。`accounts` prop 型別
    加寬成 `(ReadAccount & { balance?: number | null })[]`(呼叫端實際傳的
    `WorkspaceAccount[]` 本來就有這個欄位,只是先前收窄成 `ReadAccount[]`
    沒暴露;共享帳本場景傳的 `ReadAccount[]` 沒有餘額,此時按鈕不顯示)。
    轉出側填 `form.amount`;轉入側只在跨幣別(`showTransferFx`)時填
    `fx_amount_override`(同幣別沒有獨立可編輯的轉入金額欄位)。
  - `TransactionsPage.tsx` 的 `txDictionaryAccounts` state 型別從
    `ReadAccount[]` 寬成 `WorkspaceAccount[]`,讓 balance 欄位能靜態流通到
    `TransactionsPanel` 的 `accounts` prop(`GlobalEditDialogs.tsx` 的
    `editTxAccounts` 本來就已經是 `WorkspaceAccount[]`,不用改)。
- **Payload 組裝**(`TransactionsPage.tsx`/`GlobalEditDialogs.tsx`,兩份
  各自複製、都要同步改):
  - `feeNum`/`discountNum`/`totalAmountNum` 計算三方 fork:transfer 時
    `discountNum` 看 `discount_enabled`(不是 `fee_enabled`),
    `totalAmountNum` 直接等於使用者輸入的原始金額(不套用 base±fee∓discount
    公式)——這是實作時發現的關鍵陷阱:沿用原本判斷會讓 `finalAmountNum`
    (=`totalAmountNum`)把手續費/折損誤算進轉帳本體金額,且
    `transferToAmount` 的跨幣別換算基準也會跟著算錯。
  - payload 的 `fee_amount`/`discount_amount`/`base_amount` 依 tx_type 分流:
    transfer 時 `fee_enabled`/`discount_enabled` 各自獨立控制對應欄位是否送
    出,`base_amount` 一律不送;expense/income 維持既有的「`fee_enabled` 同時
    控制兩者」行為。
  - 編輯既有轉帳時的表單回填(`openTxEditForm`/`onOpenEditTx`/
    `duplicateOf`):`fee_enabled`/`discount_enabled` 依 tx_type 分別對應
    `fee_amount != null`/`discount_amount != null`,不像 expense/income 那樣
    兩者共用一個判斷。
- 三語 i18n(`en.ts`/`zh-TW.ts`/`zh-CN.ts`)新增 `transactions.field.toAmount`/
  `transactions.field.fillBalance`,`i18n.test.ts` 的三語 key parity 測試
  驗證過。

### 範圍外/已知限制

- 沒有新增 React 元件層級的測試——這個專案目前只有 `.test.ts` 純函式測試
  慣例(沒有 `.test.tsx`/React Testing Library/jsdom 基建),`TransactionsPage
  .tsx` 的存檔邏輯是一個大型內聯 closure,拆出可測試函式屬於額外重構,超出
  本次設計文件範圍。改以 `tsc -b` 全量型別檢查 + Cloud 後端測試(真正驅動
  餘額正確性的權威來源)把關。
- 交易列表/明細等顯示層不顯示手續費/折損金額(跟設計文件「範圍外」一致)。

## 測試

- **App**:
  - `test/repositories/transfer_fee_discount_balance_test.dart`(12 個):
    `addTransaction`/`updateTransaction` 的 fee/discount 參數寫入/保留/清空
    語意 + 7 處餘額計算方法的回歸/組合測試。
  - `test/data/migration_v46_test.dart`(3 個):schemaVersion、新欄位存在、
    既有資料讀回皆為 null。
  - `test/widgets/transfer_form_fee_discount_test.dart`(5 個):代入餘額箭頭
    填值、同幣別未開啟折損時區塊隱藏、按過箭頭後折損面板可展開、送出後
    repo 收到正確的 4 個欄位、折損超過轉入金額時驗證錯誤。
  - `test/data/sync_pull_errors_schema_test.dart`:更新 schemaVersion 斷言
    45 → 46。
  - 完整 `flutter test` 909 個測試全數通過(1 個既有 skip)。
- **Cloud 後端**(pytest):
  - `tests/test_tx_fee_discount.py`:既有的 `test_web_create_transfer_with
    _fee_discount_rejected` 改寫成 `..._allowed_amount_unchanged`(驗證 200 +
    amount 不重算 + base_amount 落 null)+ 新增負數金額仍被 schema 層 422 擋下
    的測試。
  - `tests/test_tx_transfer_fee_discount.py`(新檔,4 個):sync push 落地、
    workspace 帳戶餘額疊加、無手續費/折損回歸、淨值歷史序列疊加。
  - 全量 `pytest` 除了 2 個跟本次改動無關的既有失敗(`test_recurring
    _occurrence_update_overridden_skipped_by_update_from` 日期邊界 flaky、
    `test_accounts_parent_before_child_required` 匯入測試、以及一個既有的
    AI provider test error)全數通過,已用 `git stash` 驗證這些在改動前的
    程式碼上同樣失敗。
- **Cloud 前端**:`tsc -b` 全量型別檢查通過;`vitest run`(`apps/web`)
  117 個測試,除了 1 個跟本次改動無關的既有 i18n key 缺失(`admin
  .scheduledJobs.job.swipesmart_usage_backfill`)全數通過,同樣用 `git
  stash` 驗證為既有失敗。
