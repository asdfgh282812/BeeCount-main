# 借還款 §5.4 對象管理 + §5.5 通知中心「未結清對象清單」+ 三個記帳表單 UX 修正

日期:2026-08-24
背景:`docs/superpowers/specs/2026-08-23-debt-payables-receivables-moze-parity-design.md`
是前一天做的差異分析,列出借還款功能對標 Moze 後的落差,刻意沒有改程式碼。
這篇記錄把 §5.4(對象管理)、§5.5(通知中心未結清對象清單)實際落地的過程,
以及使用者同時回報的三個既有 UX 問題。App(本 repo)+ Server
(`../BeeCount-Cloud`,獨立 repo)兩邊都改了。

## 1. 三個記帳表單 UX 修正(純 App,不動 schema/sync)

### 1.1 欠款分頁本金金額換成自訂小鍵盤

`lib/widgets/transaction/debt_entry_form.dart` 的本金欄位原本是
`TextField` + `TextInputType.numberWithOptions`(系統小鍵盤),跟支出/收入
分頁用的自訂計算小鍵盤(`AmountCalculatorKeypad`)不一致。改成跟
`TransactionEntryFormState`/`TransferFormState` 同一套 `_amountStr`/
`_acc`/`_op` 狀態 + `_appendDigit`/`_backspace`/`_clearAll`/`_applyOp`/
`_applyEquals` 方法,`build()` 換成「大字金額顯示 + 底部固定
`AmountCalculatorKeypad`」佈局,對象/備註欄位聚焦時讓位給系統鍵盤(跟其他
分頁同一套 `_textFieldFocused` 規則)。

### 1.2 修正切到「欠款」分頁時已輸入內容不會帶過去的 bug

根因:`transaction_editor_page.dart` 的 `_applySharedFields`
([transaction_editor_page.dart:196](lib/pages/transaction/transaction_editor_page.dart))
用 `switch` 對 tabIndex 分流,`_ => null` 這個 default 分支同時吃掉
tabIndex 2(轉帳)跟 3(欠款)——切到欠款分頁時,匯出的欄位其實被誤寫進
隱藏的轉帳分頁狀態,欠款分頁本身什麼都沒拿到。

修法:
- 新增 `_debtFormKey = GlobalKey<DebtEntryFormState>()`,`_applySharedFields`
  加一個 `tabIndex == 3` 的獨立分支,不再落入轉帳的 fallback。
- `_exportSharedFields` 補上 `case 3`,讓使用者先填欠款分頁再切走也能保留
  輸入。
- `DebtEntryFormState` 新增 `applySharedFields`/`exportSharedFields`,跟
  另外兩份實作一樣是**無條件覆蓋**語意。`SharedEntryFields.merchant`(商家)
  映射到這裡的「對象」欄位——語意最接近,也是使用者從支出/收入分頁切過來
  最常見的情境。這個表單沒有交易日期/標籤欄位,`date`/`tagIds` 忽略。

`test/widgets/transaction_editor_page_tab_sync_test.dart` 新增「支出分頁
輸入內容後切到欠款 tab」的迴歸測試。

### 1.3 欠款相關交易的「編輯」改走欠款專用表單

點一筆欠款起點交易或還款交易,原本打開的是一般交易編輯表單(看不出跟欠款
的關係)。`lib/widgets/biz/transaction_detail_card.dart` 的 `_handleEdit`
已經有 `_loadRelatedDebt` 算出的 `relatedDebt`,改成依此分流:
- 還款交易(`tx.debtSyncId != null`)→ `DebtRepaymentPage`(新增
  `editingTransaction` 可選參數,回填既有金額/帳戶/日期/分類/備註,存檔時
  呼叫 `updateTransaction` 而不是 `addTransaction`——`debtSyncId` 不在
  `updateTransaction` 的參數裡,不會被動到,原本的欠款關聯自動保留)。
- 起點交易(沒有 `debtSyncId`,靠 `getDebtByOriginTransactionSyncId` 反查)
  → `DebtEditorPage`(既有的欠款編輯頁,本來就是「原本編輯的樣子」)。
- 其餘一般交易維持原本的 `TransactionEditUtils.editTransaction`。

## 2. §5.4 對象管理

### 2.1 對象改名 = 全域批次操作,不是單筆欄位編輯

設計決策:Moze 語意是「在設定裡改對象名稱會連動該對象所有記錄」,所以沒有
新增一個獨立的「對象管理頁」——讓現有 `DebtEditorPage`(唯一能編輯
`counterpartyName` 的地方)在儲存時偵測名稱有沒有變:變了就呼叫新的批次
改名方法,不是把新名字當成「只改這一筆」的欄位更新。`DebtListPage`/Web
`DebtsPanel.tsx` 都不用新增頁面或彈窗。

**App**:
- `DebtRepository`/`LocalDebtRepository` 新增
  `renameCounterparty({ledgerId, oldName, newName}) -> Future<int>`(受影響
  筆數),`LocalDebtRepository` 在一個 `db.transaction()` 內逐筆
  `UPDATE`。`LocalRepository` 的 override 先查出受影響的 debt id(改名前
  查,改完就再也查不到符合舊名稱的列了),呼叫底層改名後對每個 id 各自呼叫
  `_recordDebtChange(id, 'update')`,確保每筆都各自產生一筆 ledger-scoped
  change 讓 sync 推送。
- `DebtEditorPage._saveDebt`:編輯模式下,`counterpartyName` 跟原值不同就
  先 `renameCounterparty`,`updateDebt` 不再帶 `counterpartyName`。對象欄位
  下方加一行小字提示「修改對象名稱會套用到此對象名下所有記錄」。

**Server**(`../BeeCount-Cloud`):
- 新檔案 `src/routers/write/debts_rename_counterparty.py`
  (`POST /ledgers/{id}/debts/rename-counterparty`),仿照
  `transactions_batch_delete.py` 的結構(不走共用的單實體 `_commit_write`,
  手捲同一套 lock + build snapshot + diff + commit 流程,因為要一次改多筆
  同類型實體)。`_OWNER_ONLY_ROLES`(跟單筆 debt create/update/delete 一致)。
  找不到任何符合 `old_counterparty_name` 的記錄回 400。
- `src/snapshot_mutator.py` 新增 `rename_debt_counterparty(snapshot,
  payload)`——在 snapshot 的 `debts` 列表裡找出符合舊名稱的所有項目一次改掉。
- `src/routers/write/__init__.py` 註冊新 router。
- Web:`api-client` 新增 `renameDebtCounterparty` 包裝 +
  `DebtRenameCounterpartyPayload`/`Response` 型別;`DebtsPage.tsx` 的
  `onSubmit` 編輯分支偵測名稱變化後改呼叫這個端點,不再把新名字丟進
  `updateDebt`;`DebtsPanel.tsx` 對象欄位下方加同款提示文案。

單筆 `PATCH /ledgers/{id}/debts/{debt_id}` 的 `counterparty_name` 語意維持
不變(純改這一筆)——批次連動是兩邊 UI 主動選擇呼叫新端點的結果,不是既有
PATCH 端點暗地 cascade,避免其他呼叫者被意外的副作用影響。

### 2.2 「排除計入總額」開關

依使用者決策:只影響淨資產/總額統計,不影響清單或通知的可見性。

**App**:
- `lib/data/db.dart`:`Debts` 加 `excludedFromTotal`(`BoolColumn`,預設
  `false`),`schemaVersion` 41→42。
- `getNetDebtBalance`/`getDebtBalancesByLedgerForAllLedgers`
  (`local_debt_repository.dart`)各自多一行 `if (debt.excludedFromTotal)
  continue;`。`getDebtsWithStatus`/`getAllDebts`(清單用)刻意不套用這個
  過濾。
- Sync:`entity_serializer.dart::serializeDebt` 恆發這個欄位(跟
  `direction` 同款,不用 `if != null` 包);`sync_engine_apply.dart` 的
  `_applyDebtChange` 無條件覆蓋(缺鍵視為 `false`,不是 partial merge)。
- UI:`DebtEditorPage`/`DebtEntryForm` 都加一個開關(`SectionCard` 包
  `Row + Switch`——**不能用 `SwitchListTile`**,見下方「踩到的坑」)。
- l10n 新 key 只加進 `app_en.arb` + `app_zh_TW.arb`(既有政策,不動
  `app_zh.arb`/`app_ko.arb`)。

**Server**:跟 `UserAccountProjection.include_in_total` 同一條鏈路:
`models.py`(新欄位 + `server_default=false()`)→ 新 migration
`0049_debt_excluded_from_total.py` → `schemas.py`
(`WriteDebtCreateRequest`/`WriteDebtUpdateRequest`/`ReadDebtOut`)→
`projection.py::upsert_debt` → `sync_applier.py` 的 `_MergeSpec` →
`snapshot_builder.py`(全量 dump,恆發)→ `snapshot_mutator.py`
(`create_debt`/`update_debt`)→ `routers/read/ledgers.py::list_debts`。
目前 server/web 兩邊都沒有任何「淨資產/總額」的 rollup 會用到 debts(已
確認),這個欄位現階段只是被儲存/回傳,App 是唯一真正消費它的地方——為
未來 web 端如果也做等效總額統計預留欄位。Web `api-client`/`forms.ts`/
`DebtsPanel.tsx` 同步補上型別 + toggle(順手把已知落後的 `category_id`/
`origin_tx_id` 補進 web 型別)。

**踩到的坑**:`SwitchListTile` 包在 `SectionCard`(白底 + 圓角 +
boxShadow 的 `Container`)裡會觸發 Flutter 的
「ListTile background color or ink splashes may be invisible」斷言——
`ListTile` 系列 widget 會相對「最近的 `Material` 祖先」畫背景/水波紋,中間
夾一層有背景色的 `DecoratedBox` 會擋住。既有的 `transaction_entry_form.dart`
`SwitchListTile` 用法之所以沒事,是因為它包在 `AlertDialog` 裡(`AlertDialog`
自帶 `Material`),不是 `SectionCard`。修法:改用 `Row` + 純 `Switch`
(不是 `ListTile` 系列),兩處(`DebtEntryForm`/`DebtEditorPage`)都改。這個
問題是新增小鍵盤+欠款 tab 切換測試(`transaction_editor_page_tab_sync_test.dart`
的新案例會途經欠款分頁的完整渲染)實際跑出來抓到的,不是靠肉眼發現。

## 3. §5.5 通知中心:未結清對象清單

跟現有到期日提醒(`debt_reminders.py`,只看 3 天內到期)是不同機制——這個
清單不管有無設定到期日,只要還沒結清(`open`/`partial`)就要出現。依使用者
決策,落地為真正的 Server `Notification` 記錄(享有已讀狀態/跨裝置一致),
不是 App 端純查詢式呈現。

**Server**:新檔案 `src/services/debt_unsettled_notifications.py`
(`sync_unsettled_counterparty_notifications`),跟 `debt_reminders.py`
平行、不共用檔案(維持單一職責)。邏輯:
1. 依 `(user_id, ledger_id, counterparty_name)` 分組算出未結清總額/筆數
   (`closed_at is None and remaining > 0.01`,不看 `due_at`)。
2. 每組:有既存未讀的 `category="debt_unsettled"` 通知(按
   `ledgerId`+`counterpartyName` 比對)就更新 title/body(不動
   `created_at`/`read_at`);沒有就新建一條 `pinned=True` 的通知。
3. 上一輪還在、這一輪已經不在未結清集合裡的分組(全部結清/結案了)→ 把
   既有未讀通知標記已讀,等同「從清單消失」,不刪除歷史記錄。

註冊到既有的統一排程器(`src/services/scheduled_jobs.py`),新 job_key
`debt_unsettled_counterparties`,跟 `debt_reminders` 同 15 分鐘級距,兩者
互相獨立。`services/notifications.py` 的 `NotificationCategory` 加
`"debt_unsettled"`。

**App**(`lib/pages/notifications/notification_center_page.dart`):
- `_categoryIcon` 加 `debt_unsettled` 的 case。
- `resolveNotificationJumpTarget` 的跳轉優先序原本是
  `accountId > recurringRuleId > debtId`,加第四個分支:沒有前三者、但
  payload 帶 `counterpartyName` → 導到 `DebtListPage`(對象分組摘要沒有單
  一 debt 可指,清單頁本身筆數通常不多,不特別做「對象詳情頁」)。
- App 這裡完全不碰本地 DB/repository/sync 邏輯——通知資料 100% 來自 Server
  已存在的 `BeeCountCloudNotificationItem` 拉取管線,只是新增一個 category
  的圖示/導頁分支。

**Web**(`frontend/apps/web/src/components/NotificationBell.tsx`):
`handleJumpToDetail` 加 `counterpartyName` 分支(沒有 `debtId` 時),導到
`/app/debts`,不帶 highlight。

## 刻意不做的事

- 沒有做 §5.2(轉成支出)/§5.3(多筆合併還款)——這兩項是同一份差異分析
  文件裡列出的另外兩個落差,這次範圍只做 §5.4/§5.5 + 三個 UX 修正。
- §5.1(狀態態數 3 態 vs 4 態顯示合併)沒有動,維持現行四態
  `open`/`partial`/`settled`/`closed`。
- 沒有新增獨立的「對象管理頁」——改名功能掛在現有 `DebtEditorPage`,見上。
- 通知的「已讀狀態」是自動維護(結清後自動標記已讀),沒有讓使用者手動
  「忽略這個對象」的入口。

## 相容性

`excludedFromTotal` 跟批次改名端點都是新增,對舊版另一端(App/Server/Web
任一邊還沒升級)不會炸掉:序列化恆發但舊版讀不到的欄位會被忽略,新端點舊
版 App/Web 不會呼叫。四邊(App/Server/Web 三處程式碼 + migration)可以分開
部署,但批次改名要 Server 先部署新端點,App/Web 才能改用它。

## 測試

- **App**:`test/repositories/local/debt_repository_test.dart` 新增
  `renameCounterparty`(含跨帳本/找不到名字的邊界案例)、`excludedFromTotal`
  (含只影響總額、不影響清單的斷言)。`test/sync/debt_apply_test.dart` 新增
  `excludedFromTotal` 的 pull 路徑往返(含缺鍵視為 `false` 的全量 upsert
  語意驗證)。`test/data/notification_jump_target_test.dart` 新增
  `counterpartyName` 分支(含跟 `debtId` 互斥優先序、切帳本案例)。
  `test/widgets/transaction_editor_page_tab_sync_test.dart` 新增欠款分頁的
  tab 切換迴歸測試。`test/data/sync_pull_errors_schema_test.dart` 的
  `schemaVersion` 斷言從 41 更新成 42。全專案 `flutter analyze` 零錯誤,
  `flutter test` 全過(821 passed)。
- **Server**:`tests/test_debts.py` 新增 `excluded_from_total` 往返(REST +
  mobile push)、批次改名(成功/跨帳本隔離/找不到名字)、未結清通知(不看
  到期日/同對象多筆彙總/結清後自動已讀/手動結案跳過)共 10 個新案例。
  `tests/test_scheduled_jobs.py` 更新既有的「8 個 job」斷言成「9 個」,補上
  新 job_key 的 mock 驗證。alembic migration 本地沒有 Postgres 可跑
  upgrade/downgrade round-trip,寫法完全比照 `0048_notification_pinned.py`
  (同樣是 nullable=False + `server_default=false()` 的 boolean
  additive column),風險評估為低,建議部署前在 staging 手動跑一次確認。
  Web 前端用 `tsc -b`(monorepo project references,涵蓋
  `api-client`/`web-features`/`apps/web` 三個 package)整個編譯零錯誤,
  沒有起 dev server 手動點過 UI(無瀏覽器環境)。
