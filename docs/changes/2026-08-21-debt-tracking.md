# 借還款(Debt Tracking)

日期:2026-08-21
背景:BeeCount Cloud(web/server,獨立 repo)已有「借還款」頁,是完全
獨立於 App 的 sync entity(`debt`),App 端目前完全沒有實作(見
`docs/CLOUD_SYNC_INTEGRATION.md` §1 的落差表)。這次把它搬到 App 端,
資料模型完全比照 Cloud 既有實作(direction/principalAmount 建立後不可改、
沒有獨立的「還款」實體、狀態即時算不落地存),UI 呈現參考
`doc.moze.app/record/payables-receivables`(Moze「應收應付款項」的設計
理念)。範圍決策(使用者確認):一次做完含雲端同步(不分階段);帳戶列表
入口做成「純 UI 虛擬入口」(不是真 `Account` row,不走帳戶同步);淨欠款
餘額計入淨資產統計。

**這次沒做、刻意延後**:交易表單裡的「關聯欠款」下拉(可從任意交易連結/
新建欠款)、交易明細頁與欠款卡片的雙向跳轉、到期提醒通知。原因:
`transaction_entry_form.dart`/`transaction_detail_card.dart`/
`transaction_editor_page.dart` 這幾個檔案當下有另一個未提交的拆帳
(`transaction_splits`)功能正在進行中,深度改動這些檔案風險較高,容易
互相衝突。還款本身走的是獨立的 `DebtRepaymentPage`(見下),不受影響——
只是「從既有普通交易反向連結/建立欠款」這個附加體驗延後。

## 1. 資料模型:新表 `Debts` + `Transactions.debtSyncId`

**改了什麼**:`lib/data/db.dart` 新增 `Debts` 表(ledger-scoped,同
`Budgets`/`Ledgers` 那組模式):`id`/`syncId`/`ledgerId`/`direction`
(`payable`/`receivable`)/`counterpartyName`/`principalAmount`/`dueAt`/
`note`/`closedAt`/`createdAt`/`updatedAt`。`Transactions` 表新增
`debtSyncId`(text?)——**存 syncId 字串,不是本地 int FK**,同
`recurringRuleId` 的做法(不是 `categoryId`/`accountId` 那種本地 int +
`*SyncIdOverride` 的模式),因為欠款是 ledger-scoped 實體,本地 int id
跨裝置不保證一致,存 syncId 才能在對端還沒 pull 到新欠款時仍正確引用。
`schemaVersion` 38 → 39。

**為什麼沒有幣別欄位**:跟 Cloud 完全一致——欠款本金一律以帳本記帳幣種
計,不支援欠款本身跨幣種(還款交易仍可用既有的 `currencyCode`/
`nativeAmount` 多幣種機制)。

**狀態不落地存**:`remainingAmount`/`status`(`open`/`partial`/`settled`/
`closed`)一律在讀取時即時算(掃 `Transactions.debtSyncId` 命中的還款
交易加總本金扣還款),對齐 Cloud `read_debt_projection` 的設計,理由同
`installment_plan.paid_periods`——避免多寫入路徑各自維護衍生欄位。
`closedAt` 優先於金額判斷:可以在未還清時手動結案(呆帳/不再追蹤)。

## 2. Repository:`DebtRepository` + `LocalDebtRepository`

**改了什麼**:新增 `lib/data/repositories/debt_repository.dart`(接口)+
`local/local_debt_repository.dart`(實作),掛進 `BaseRepository`/
`LocalRepository`(委托模式,同 `BudgetRepository` 的結構)。CRUD:
`createDebt`/`updateDebt`(只能改 counterpartyName/dueAt/note,principal/
direction 不提供)/`closeDebt`/`reopenDebt`/`deleteDebt`(已有還款記錄會
拋 `StateError`,對齐 Cloud 的 `DEBT_HAS_REPAYMENTS` 守衛)。查詢:
`getDebtsWithStatus`/`getDebtWithStatus`/`getDebtRepaymentTransactions`/
`getNetDebtBalance(ledgerId)`/`getDebtBalancesByLedgerForAllLedgers`
(跨帳本聚合,供淨資產統計用)。`TransactionRepository.addTransaction`
新增 `debtSyncId` 參數,新增 `setTransactionDebtLink` 方法(對齐既有的
`setTransactionReconciled`/`setTransactionDeferredPosting` 專用 setter
慣例)。`LocalRepository.deleteLedger` 級聯清理同 budgets 一起處理,登記
`debt:delete` change。

## 3. Sync 同步:新 entityType `debt`(ledger-scoped)

**改了什麼**:`entity_serializer.dart` 新增 `serializeDebt`,`dueAt`/
`note`/`closedAt` 恆發(同 `reconciledAt`)——這三個欄位都有明確的清空
動作(`clearDueAt`/`clearNote`/`reopenDebt`),省略會讓清空/重開同步不
出去。`serializeTransaction` 新增 `debtId` 鍵(讀 `tx.debtSyncId`,恆發)。
`sync_engine_serialization.dart` 的 `_serializeEntityForPush`/
`_pushAllEntities` 各加一個 `debt` case/迴圈,同 `budget`/`recurring_rule`
模式。`sync_engine_apply.dart` 新增 `_applyDebtChange`(按 syncId
upsert/delete,ledger 外鍵用 `_resolveLedgerIdBySyncId` 換本地 int id,
本地未就緒就跳過不建孤兒),`_applyTransactionChange` 新增 `debtId` 鍵的
「缺鍵不覆蓋」處理(同 `recurringRuleId`)。欄位命名對齐 Cloud
`sync_applier.py::_LEDGER_MERGE_SPECS["debt"]`。

## 4. 淨資產統計:欠款計入淨資產

**改了什麼**:`LocalRepository.getNetWorthBreakdown()`/
`getNetWorthBreakdownByCurrency()` 疊加跨帳本的 receivable/payable 未結
餘額(receivable 算資產、payable 算負債,closed 的欠款不計入)。因為
`Accounts` 是 user-global、淨資產本來就是跨帳本聚合的,欠款雖是
ledger-scoped 也要用跨帳本版本(`getDebtBalancesByLedgerForAllLedgers`),
否則會漏掉非當前帳本的欠款。

## 5. UI

**改了什麼**:
- `lib/pages/debt/debt_list_page.dart`:欠款列表,依到期日排序,每張卡片
  顯示對象/方向/狀態徽章/剩餘金額+進度條,可展開看還款記錄明細
  (`_RepaymentList`)。
- `lib/pages/debt/debt_editor_page.dart`:新增/編輯欠款,direction/
  principalAmount 編輯時鎖住(對齐不可改的資料模型決策)。
- `lib/pages/debt/debt_repayment_page.dart`:記錄還款/收款——對齐 Cloud
  web 的設計(「還款是獨立小頁面,不是走完整交易表單」),只收金額
  (預填剩餘金額)/帳戶(`AccountSelector`)/日期/備註,建出一筆帶
  `debtSyncId` 的普通 expense/income 交易,不需要分類。
- `lib/pages/account/accounts_page.dart`:淨資產卡下方新增
  `_DebtEntryCard` 虛擬入口(純 UI,不是真帳戶),顯示跨帳本淨應收/應付,
  點擊導到 `DebtListPage`(該頁本身是 ledger-scoped,只顯示當前帳本——
  入口卡片範圍與導覽目標範圍刻意不同,同 Moze「應收應付款項」彙總帳戶
  本身只是導覽入口的角色一致)。
- `lib/providers/debt_providers.dart`:`debtsRefreshProvider`(手動刷新
  計數器,同 `budgetRefreshProvider`——`remainingAmount`/`status` 跨表算,
  單純 watch `Debts` 表不會在還款交易寫入時重算)+ 衍生的
  list/single/repayments/netBalance provider。

**l10n**:只加到 `app_en.arb`/`app_zh_TW.arb`(既定政策,不再維護
`app_zh.arb`/`app_ko.arb`)。

## 測試

- `test/repositories/local/debt_repository_test.dart`:狀態推導四態、
  手動結案優先於金額判斷、刪除守衛、`clearDueAt`/`clearNote`、
  跨帳本淨餘額聚合。
- `test/sync/debt_apply_test.dart`:pull apply 的 insert/全量覆蓋覆蓋
  (含 `closedAt`)/delete/孤兒帳本跳過,以及交易 payload 的 `debtId`
  鍵的恆發/缺鍵不覆蓋語意。
