# 欠款功能修正:帳戶選擇器換新 + 新增分類 + 起點交易可觸發還款

日期:2026-08-23
背景:延續 `docs/changes/2026-08-21-debt-tracking.md`/
`2026-08-22-debt-entry-tab-and-account-linkage.md` 的借還款功能,使用者
實際使用後回饋三個問題:①欠款相關表單的帳戶選擇器沒跟上其他表單改版
②欠款/還款想要能選分類 ③交易明細卡希望能直接觸發還款,而不是只能從欠款
列表頁進入。本篇記錄這三個問題的修正,不含通知釘選(見同日的
`2026-08-23-notification-pinning.md`)。

## 1. 帳戶選擇器換成 `AccountCardPicker`

**改了什麼**:三個仍在用舊版橫滑 chips 元件(`AccountSelector`,已刪除)
的呼叫點都換成 `AccountCardPicker.show(...)`(彈出式卡片選擇,支出/收入/
轉帳表單已經在用):
- `lib/widgets/transaction/debt_entry_form.dart`
- `lib/pages/debt/debt_editor_page.dart`
- `lib/pages/debt/debt_repayment_page.dart`

三個檔案都改成同一個模式:狀態多存一個 `Account? _account`(純顯示用),
`_pickAccount()` 呼叫 `AccountCardPicker.show` 後用 `repo.getAccount(id)`
補上顯示名稱,原本的可點擊列改成一個 `InkWell` + `Container`(圖示 + 帳戶
名 + chevron),視覺對齐 `transaction_entry_form.dart` 的 `_buildAccountRow`。

**為什麼順手刪掉 `AccountSelector`**:換完三個呼叫點後,`lib/` 下已經沒有
任何地方真的 import/使用這個 widget(只剩測試檔案的註解提及),留著一個
沒人用的舊 picker 容易誤導之後的開發者以為它還在用,直接刪除。

## 2. 欠款 / 還款新增「分類」欄位

原始設計(§2.5 Phase 3)刻意讓欠款/還款不需要分類——這在 App 跟 BeeCount
Cloud 上其實原本是一致的(不是使用者原先以為的「兩邊沒對齊」),但使用者
明確要求要能選分類,所以這次是新增功能,不是修 bug。

### App 端

- `lib/data/db.dart`:`Debts` 表新增 `categoryId`(`IntColumn`,nullable,
  不宣告 FK,跟 `Transactions.categoryId` 同款)。`schemaVersion` 40→41,
  `onUpgrade` 加 `if (from < 41)` 區塊(這個區塊同時處理需求4的
  `originTransactionSyncId`,見下)。
- `DebtRepository`/`LocalDebtRepository`/`LocalRepository`:
  `createDebt`/`createDebtWithOriginTransaction` 新增 `categoryId` 參數,
  `updateDebt` 新增 `categoryId`/`clearCategoryId`(跟既有 `dueAt`/
  `clearDueAt` 同款「顯式清空」語意)。
- Sync:`entity_serializer.dart::serializeDebt` 新增 `categorySyncId` 參
  數,恆發(不是 `if != null` 才發)——因為分類有明確的清空動作,省略或只
  在非 null 才發會讓「清空」這個動作永遠同步不出去,跟 `dueAt`/`note`/
  `closedAt` 同一套既有慣例。`sync_engine_apply.dart::_applyDebtChange`
  照抄 `_applyBudgetChange` 的 pattern,用 `_resolveCategoryIdBySyncId`
  把 wire 上的 `categoryId`(syncId 字串)解析成本地 int id。
  `sync_engine_serialization.dart` 兩個呼叫點(單筆 push + `fullPush` 全
  量快照)都補上「本地 categoryId → categorySyncId」的查表邏輯。
- UI:`DebtEntryForm`/`DebtRepaymentPage`/`DebtEditorPage`(create 與 edit
  模式都補,理由見下)都新增一個分類選擇列,呼叫既有的
  `showCategorySelector(...)`(`lib/widgets/biz/category_selector_dialog.dart`,
  已被搜尋頁/週期規則編輯頁等用過的自帶對話框,不用重新做 picker)。分類
  的 `type`(income/expense)跟隨欠款方向:payable → income,receivable
  → expense,跟起點/還款交易本身的 `type` 判斷邏輯一致。方向改變時會清掉
  已選分類(避免帶著錯誤 type 的分類送出)。
- **範圍決策**:計畫原本只提到 `DebtEntryForm`/`DebtRepaymentPage`,但
  `DebtEditorPage` 是同一個功能的第二個入口(`debt_list_page.dart` 的新
  增/編輯都導到這裡)——只改前兩個會變成「同一個功能兩個入口,一個能選分
  類一個不能」,所以一併補上,`DebtEditorPage` 的 edit 模式也能改分類
  (`updateDebt(categoryId:, clearCategoryId:)`)。
- `debt_repayment_page.dart` 檔案開頭「分類留空(還款不需要分類)」的舊
  註解已更新,不再誤導。

### BeeCount Cloud 端(`/Users/andy/BeeCount-Cloud`,獨立 repo)

- Alembic migration `0047_debt_category_and_origin_tx.py`(跟需求4的
  `origin_tx_sync_id` 共用同一個 migration,都是同一張表的 additive
  nullable column):`read_debt_projection` 加 `category_sync_id
  VARCHAR(255)`。
- `src/models.py`:`ReadDebtProjection` 加對應欄位。
- `src/sync_applier.py`:`_LEDGER_MERGE_SPECS["debt"]` 加
  `("categoryId", "category_sync_id")`。
- `src/projection.py::upsert_debt`:落地這個欄位。
- `src/snapshot_builder.py`:debt 的全量快照 select/輸出補上這欄
  (`if cat_sid: d["categoryId"] = cat_sid`,跟 `installment_plans` 同款
  寫法)。
- `src/snapshot_mutator.py::create_debt`/`update_debt`:接受
  write-request 帶入的 `category_id`,`update_debt` 支援清空。
- `src/schemas.py`:`WriteDebtCreateRequest`/`WriteDebtUpdateRequest` 加
  `category_id`;`ReadDebtOut` 加 `category_id`(**不**加
  `category_name`——查證後發現 `installment_plan` 的
  `category_id`/`ReadInstallmentPlanOut` 這個更貼近的先例本身就沒有做
  `category_name` 反查/denormalize,直接照抄這個更準確的先例,而不是
  transaction 那個看起來相似但實際場景不同的 pattern)。
- `src/routers/read/ledgers.py::list_debts`:回傳時帶上
  `category_id: row.category_sync_id`。
- **沒有加任何 category 存在性驗證**——這個 codebase 對所有實體的 foreign
  id 都是零驗證(`_shared.py` 明文記載這個慣例),debt 沒理由破例。

## 3. 交易明細卡新增「還款」按鈕(涵蓋起點交易 + 還款交易)

使用者要求還款按鈕要出現在「該筆債務所有相關交易」上。原本只有還款交易本
身帶 `Transactions.debtSyncId`,欠款建立時的起點交易故意不帶(避免污染
`remainingAmount` 的加總,見 `debt_repository.dart` 既有文檔),所以需要
新增一個不影響加總邏輯的反向連結欄位才能讓起點交易也能被辨識。

**設計決策**:新增欄位放在 `Debts.originTransactionSyncId`(欠款側記住起
點交易的 syncId),而不是在 `Transactions` 上加一個新欄位。理由:
`LocalTransactionRepository.addTransaction` 本來就接受外部傳入的
`syncId` 參數並會使用它,而 `LocalDebtRepository.createDebt` 內部自己生
成 `syncId`、沒有 override 參數——所以「先在呼叫端生成起點交易的
syncId,傳給 `addTransaction(syncId: ...)`,再把同一個值傳給
`createDebt(originTransactionSyncId: ...)`」完全不需要調整
`LocalRepository.createDebtWithOriginTransaction` 現有的「先建交易、後建
欠款」呼叫順序。如果反過來在 `Transactions` 加欄位,欠款的 syncId 在建交
易那一刻還不存在,得改呼叫順序或多一次 UPDATE,改動面更大。這個新欄位
剛好可以跟需求2的 `categoryId` 共用同一批要改的 server 端檔案。

### App 端

- `lib/data/db.dart`:`Debts` 加 `originTransactionSyncId`(`TextColumn`,
  nullable),跟需求2的 `categoryId` 共用同一個 v41 migration block。
- `DebtRepository`/`LocalDebtRepository`:`createDebt` 新增
  `originTransactionSyncId` 參數(只給 `createDebtWithOriginTransaction`
  內部用,一般呼叫端不該傳);新增
  `Future<Debt?> getDebtByOriginTransactionSyncId(String syncId)`。
- `LocalRepository.createDebtWithOriginTransaction`:先
  `final originTxSyncId = _uuid.v4();`,依序傳給 `addTransaction(syncId:
  originTxSyncId, ...)` 跟 `createDebt(originTransactionSyncId:
  originTxSyncId, ...)`,仍在同一個 `db.transaction()` 內。
- Sync:`serializeDebt` 加 `originTransactionSyncId` → wire key
  `originTxId`(只在非空時才發,這個連結建立後不會變,不需要清空語意);
  `_applyDebtChange` 把 `payload['originTxId']` 原文寫入,**不**解析成本
  地 id——這是 syncId 對 syncId 的純文字連結,指向的交易未必已經同步下
  來,查詢時用 `getDebtByOriginTransactionSyncId` 按 syncId 反查,不是走
  本地外鍵。
- **`lib/widgets/biz/transaction_detail_card.dart`**(使用者實際會看到的
  部分):`_DetailBundle` 新增 `DebtWithStatus? relatedDebt`;
  `_loadBundle()` 新增 `_loadRelatedDebt`——若交易帶 `debtSyncId`(還款交
  易)直接 `getDebtBySyncId`,否則若交易有 `syncId` 就用
  `getDebtByOriginTransactionSyncId` 反查(涵蓋起點交易)。`_buildHeader`
  在既有 5 個 IconButton(關閉/退款/刪除/複製/編輯)中插入第 6 個「還款」
  按鈕(`Icons.payments_outlined`),只有 `relatedDebt` 存在且狀態不是
  `settled`/`closed` 時才顯示(直接不顯示,不是顯示 disabled——對齐
  `debt_list_page.dart` 自己的 `canRepay` 判斷邏輯與 UX 慣例)。按鈕的
  `onPressed` 照抄既有 `_handleEdit`/`_handleRefund` 的模式(先關掉卡片
  的 bottom sheet,再用 `hostContext` push `DebtRepaymentPage`)。

### BeeCount Cloud 端

跟需求2共用同一個 migration/同一組檔案(`models.py`/`sync_applier.py`/
`projection.py`/`snapshot_builder.py`):`read_debt_projection` 加
`origin_tx_sync_id`,`_LEDGER_MERGE_SPECS["debt"]` 加 `("originTxId",
"origin_tx_sync_id")`。**只在 `snapshot_mutator.py::create_debt` 處理**
(不開放給 `update_debt`/`WriteDebtUpdateRequest`)——這個連結建立後永遠
不會變,沒有「清空/重設」的場景,不需要暴露成可更新的欄位。web 端目前沒
有「建立欠款連帶起點交易」的流程,所以 web 建立的欠款這欄會維持 null,這
是正確的(沒有起點交易可以連結)。

## 刻意不做的事

- 沒有對 `categoryId`/`originTxId` 做任何存在性/擁有權驗證,對齐這個
  codebase 對所有 foreign id 的既有零驗證慣例。
- 沒有在還款/起點交易之間互相連動分類——分類是各自獨立選的,不會「選了
  起點交易的分類,還款交易自動帶入同一個分類」這種行為。
- 交易明細卡的還款按鈕沒有做「已結清就 disable 並顯示原因」的 tooltip,
  直接隱藏,對齐 `debt_list_page.dart` 既有的 UX(不是新規則)。

## 相容性

Server 端 push payload 是無 schema 驗證的 dict,新欄位對舊版另一端是靜默
忽略,不會炸掉;新版 app 對舊版 server push 這些新欄位會被忽略、新版
server 對舊版 app pull 這些新欄位會被忽略但不影響既有欄位——四項改動可以
server 跟 app 分開部署。

## 測試

- `test/repositories/local/debt_repository_test.dart`:更新既有的
  `createDebtWithOriginTransaction` 案例斷言(起點交易透過
  `originTransactionSyncId` 被欠款反向記住,而不是完全沒有連結),新增
  `getDebtByOriginTransactionSyncId` 反查案例(含還款交易不該被誤認成起
  點交易的反例)、`categoryId` 設定與清空案例。
- `test/data/notification_jump_target_test.dart`:見
  `2026-08-23-notification-pinning.md`(跟這篇是分開的通知功能,但兩者共
  用同一批 debt 相關 fixture)。
- `test/data/sync_pull_errors_schema_test.dart`:既有的
  `schemaVersion` 斷言從 40 更新成 41。
- UI 層(分類選擇列、還款按鈕)沒有新增 widget test,靠
  `flutter analyze`(零錯誤)跟手動驗證把關。
