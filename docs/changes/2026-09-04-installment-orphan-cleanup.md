# 分期付款孤儿数据清理(刪帳本漏 cascade)

## 问题

使用者回报:首頁淨資產卡片下方的「分期付款」入口顯示 NT$1530「尚有應繳」,但點進去的分期付款列表頁顯示「尚無分期計畫」(空)。使用者的帳本切換選單裡只有 1 個帳本,一度懷疑是別人帳號的資料混進來。

排查後排除了資料隔離/跨帳號污染:本地 SQLite 是單裝置單份、帳本切換選單查詢整表無過濾、雲端 pull apply(`sync_engine_apply.dart` 的 `_resolveLedgerIdBySyncId`)解析不到本機對應帳本就直接跳過寫入,不会制造跨帳号孤儿引用。

真正根因是 [`LocalRepository.deleteLedger()`](../../lib/data/repositories/local/local_repository.dart)。這個方法在 v39(debt)/更早(budget)已經修過「刪帳本要順便清掉 ledger-scoped 子表,否則變成 `ledgerId` 懸空的孤兒行」,但 v49 新增的 `installment_plans`/`installment_periods` 沒有跟進這個模式。使用者之前刪過一個帳本,該帳本底下建立過的分期付款因此原地留在資料庫裡,`ledgerId` 指向一個已經不存在的帳本。

- [`_InstallmentEntryCard`](../../lib/pages/account/accounts_page.dart)(首頁摘要卡片)用 `getOutstandingPrincipalAllLedgers()` 直接對 `installment_periods` 整表加總、不過濾 `ledgerId`,所以撈到了這筆孤兒本金,顯示 NT$1530。
- 分期付款列表頁用 `getInstallmentPlansWithStatus(ledgerId)`,只查目前帳本,孤兒資料的舊 `ledgerId` 對不上,顯示為空。

## 修改

1. **[`local_repository.dart`](../../lib/data/repositories/local/local_repository.dart) `deleteLedger()`**:比照既有的 budgets/debts 處理,刪帳本時一併查出並刪除該帳本下的 `installmentPlans`/`installmentPeriods`,對已有 `syncId` 的行登記 `installment_plan:delete`/`installment_period:delete` 的 `local_changes`,讓雲端(BeeCount Cloud)也同步清掉。沒開雲端同步(`changeTracker == null`)的既有分支維持原樣,跟 budgets/debts 目前的行為一致,不在此次範圍內處理。

2. **[`local_installment_repository.dart`](../../lib/data/repositories/local/local_installment_repository.dart) `getOutstandingPrincipalAllLedgers()`**:加上 `INNER JOIN ledgers`,只加總「帳本仍然存在」的分期期數,作為第二道防線——即便未來又有類似的 cascade 遺漏,也不會讓孤兒本金污染首頁摘要卡片。

3. **`db.dart` v53 遷移**(`schemaVersion` 52→53):一次性清理使用者現有裝置上已經累積的孤兒行——按「`ledger_id` 在 `ledgers` 表裡找不到」刪除 `installment_periods`/`installment_plans`,並對有 `syncId` 的孤兒行登記 `local_changes` delete,讓雲端也一併清掉(沒開雲端同步時這幾行插入是 no-op,因為 push 循環本身不會跑)。跟 v52 的做法一致(見 [2026-09-04-sync-base-amount-backfill.md](2026-09-04-sync-base-amount-backfill.md)):純 SQL、只處理已經卡住的舊資料,不影響其餘欄位。

## 測試

新增 [`test/data/migration_v53_test.dart`](../../test/data/migration_v53_test.dart),覆蓋:孤兒行(plan+period)被清除、`local_changes` 正確登記、`sync_id` 為 null 的孤兒只刪不登記、`ledgerId` 仍存在的正常資料不受影響。

## 範圍外

- `_DebtEntryCard`(借還款入口卡片)理論上是同一種「入口跨帳本聚合、列表頁限定當前帳本」的設計模式,但 debt 的 `deleteLedger` cascade 早在 v39 就已經處理,沒有這次遇到的孤兒資料問題,故未一併改動。
- 沒有把 `installmentPlanMissingLedger`/`installmentPeriodMissingLedger` 加進既有的孤兒資料掃描器(`lib/services/maintenance/orphan_scanner.dart`,對照 A1 `budgetMissingLedger` 的既有模式)。v53 遷移已經一次性清乾淨所有使用者的現有孤兒資料,且 `deleteLedger()` 的根因已修,後續不應該再產生新的這類孤兒;如果之後想让「資料維護」頁面也能自助偵測同類問題,可以再補。

## 後續更新(同日):v53 沒能解決,真正根因是另一條孤兒來源

使用者套用 v53 後重新建置回報問題依舊。重新排查發現:**使用者裝置上其實只有 1 個帳本**,代表這筆孤兒的 `ledgerId` 指向的是**現存**帳本,不是已刪除的帳本——v53「`ledger_id` 在 `ledgers` 表裡找不到」的清理條件對這種孤兒完全不生效,先前的診斷方向錯了。

真正根因是 [2026-09-03-installment-tracking-delete-sync-fixes.md](2026-09-03-installment-tracking-delete-sync-fixes.md) 問題A記錄過的既有 race:刪除一個分期計畫是一次操作產生 `N*2+1` 筆獨立 change(每期一筆 `installment_period:delete`、每期生成交易一筆 `transaction:delete`、加 1 筆 `installment_plan:delete`),推送/拉取之間存在窗口期。當時的修法是 A3(`applyRemoteChange` 套用前檢查 `hasPendingLocalDelete`,防止「未來再發生」)+ A4(`orphan_scanner.dart`/`orphan_cleaner.dart` 新增 A11/A12/A13 三種偵測,作為使用者可以在「設定→資料管理→資料維護」自助清理**既有**孤兒的工具)——但沒有回頭把使用者裝置上當時已經卡住的孤兒資料一次清乾淨,也沒有讓 `getOutstandingPrincipalAllLedgers()` 對這類孤兒免疫。

- [`_applyInstallmentPlanChange`](../../lib/cloud/sync/sync_engine_apply.dart) 的 `delete` 分支只刪 `installment_plans` 那一列,不會連帶清 `installment_periods`(靠 `plan_sync_id` 字串反查,不是本地外鍵)或 `transactions.installment_plan_sync_id` 的引用——跟本地 `deleteInstallmentPlan()`(會在同一個 transaction 裡把 tx/period/plan 三者一起清)刻意不對稱,因為個別 entity 的 delete 本來就是各自獨立同步的 change。
- 一旦 race 導致 `installment_period`/`transaction` 的 delete change 沒能跟 `installment_plan` 的 delete change 一起套用,就會留下「`installment_periods.plan_sync_id` 指向一個已經不存在的 plan」的孤兒(對照 `orphan_scanner.dart` 的 A12 `installmentPeriodMissingPlan`)。這個孤兒的 `ledgerId` 仍是使用者當前唯一的那個帳本,v53 的檢查條件天生看不見它。

### 修改(補上)

1. **[`local_installment_repository.dart`](../../lib/data/repositories/local/local_installment_repository.dart) `getOutstandingPrincipalAllLedgers()`**:在既有的 `INNER JOIN ledgers` 之外,再加一個 `INNER JOIN installment_plans`(按 `planSyncId` = `installmentPlans.syncId`)。這才是真正對症的防線——只加總「所屬 plan 仍然存在」的分期期數,跟 A12 的偵測條件完全對齊。
2. **`db.dart` v54 遷移**(`schemaVersion` 53→54):比照 `orphan_cleaner.dart` 既有的 A11/A12 語意,一次性清掉使用者裝置上已經卡住的舊孤兒——`installment_periods.plan_sync_id` 找不到對應 plan 的直接刪除該筆 period(純排程元資料,不影響它產生的真實交易);`transactions.installment_plan_sync_id` 找不到對應 plan 的只清空這個引用欄位,交易本身(使用者真實的消費紀錄)保留。純本地清理,不登記 `local_changes`——這批資料在 server 端本來就已經是「plan 已刪」的正確狀態,不需要再推一次修正。

### 測試

新增 [`test/data/migration_v54_test.dart`](../../test/data/migration_v54_test.dart)(孤兒 period 被刪、孤兒交易只清引用不刪交易本身、plan 仍存在時不受影響),以及 [`test/repositories/local/installment_repository_test.dart`](../../test/repositories/local/installment_repository_test.dart) 新增 `getOutstandingPrincipalAllLedgers` 測試群組(用直接刪 `installment_plans` 行模擬 race 殘留的孤兒場景,驗證不再計入「尚有應繳」)。

### 給使用者的immediate workaround

不想等下次重新建置的話,現在就可以在「設定 → 資料管理 → 資料維護」用既有的孤兒資料掃描/清理工具,勾選偵測到的分期期數/交易項目手動清掉——這是 2026-09-03 就做好、專門為這個 race 準備的自救工具,只是使用者可能不知道它的存在。
