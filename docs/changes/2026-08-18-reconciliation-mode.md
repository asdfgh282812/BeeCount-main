# 對帳模式(信用卡逐筆核對清單)

日期:2026-08-18
背景:BeeCount Cloud(web/server,獨立 repo `../BeeCount-Cloud/`)已依 Moze
官方文件(`doc.moze.app/reconciliation/statement-mode`)實作對帳模式——顯示
信用卡「這期帳單」的交易清單,逐筆勾選確認是否已出現在銀行帳單上,未出現的
可標記「延後入帳到下一期」。這次把同一套邏輯搬到 App 端。範圍決策(使用者
確認):核心對帳流程(確認/延後/週期瀏覽/批次清除/新增遺漏交易)+ 轉入轉帳
併入清單 + 簡化版回饋金徽章(**不**做 Cloud 端依 `card_reward_rule` 反查、
同方案多筆回饋合併成一列的邏輯——App 端本來就沒有 `card_reward_rule` 這個
實體,详见「刻意排除的範圍」)。

## 1. 資料模型:`Transactions` 新增 `reconciledAt`/`deferredPostingAt`

**改了什麼**:`lib/data/db.dart` 的 `Transactions` 表加兩個 nullable
`DateTimeColumn`:`reconciledAt`(已確認對帳的時間戳)、`deferredPostingAt`
(延後入帳的目標日)。`schemaVersion` 36 → 37,`MigrationStrategy.onUpgrade`
補一個 `if (from < 37)` 區塊,單純 `ALTER TABLE ... ADD COLUMN`(照抄
v33/v34 的最短範例,不用像 v36 那樣重建表)。

**為什麼**:對齊 BeeCount Cloud 的 `read_tx_projection.reconciled_at`/
`deferred_posting_at`——這個設計刻意不用獨立的 reconciliation 表,一筆交易
只需要記「有沒有被對過帳」跟「延後到哪天」兩個狀態,靠這兩個欄位本身就夠,
不需要額外的關聯表。

## 2. Sync 同步契約:恆發語意(不是「有值才發」)

**改了什麼**:
- `lib/cloud/sync/entity_serializer.dart::serializeTransaction` 新增
  `'reconciledAt': tx.reconciledAt?.toUtc().toIso8601String()`、
  `'deferredPostingAt': tx.deferredPostingAt?.toUtc().toIso8601String()`,
  **恆發**(值可能是 `null`),跟 `merchant`/`excludeFromStats` 同一種寫法。
- `lib/cloud/sync/sync_engine_apply.dart::_applyTransactionChange` 用
  `payload.containsKey('reconciledAt')`/`containsKey('deferredPostingAt')`
  判斷 key 是否存在,存在才寫(值可以是 `null`,代表清空),不存在則
  `d.Value.absent()`(保留本地既有值)。

**為什麼**:這兩個欄位有明確的清空動作(使用者在對帳清單裡取消確認、或點
「取消延後」),必須讓 `null` 值本身也能同步過去,不能省略。但同時要相容
沒有這個功能的舊版 App(不帶這兩個 key 的 payload 不該把已有的確認/延後標記
清空)——所以是「恆發 + containsKey 保護」的組合,不是單純「有值才發」
(那樣使用者取消確認就永遠同步不出去)也不是單純「一律覆寫」(那樣舊版
App 的 partial update 會把新版裝置設定的標記衝掉)。測試見
`test/sync/transaction_reconciliation_apply_test.dart` 三個案例(插入帶值/
缺鍵保留/帶鍵值為 null 清空)。

## 3. 週期語意:跟信用卡帳單彙總卡片共用同一套週期計算,但 offset 基準不同

**改了什麼**:新增 `lib/utils/reconciliation.dart`:
- `statementCyclePeriod(billingDay, cycleOffset)` = `billingCyclePeriod(billingDay,
  cycleOffset - 1)`——刻意內部多減 1。
- `effectiveDate(tx)` = `tx.deferredPostingAt ?? tx.happenedAt`(入帳歸屬日)。
- `defaultDeferredPostingDate(billingDay, cycleOffset)` = 下一期帳單第一天。
- `signedStatementAmount(tx)`:expense 正、income/轉入負。
- `kRewardCategoryName = '回饋金'` + `isRewardCategoryName()`。

**為什麼**:既有 `lib/utils/card_reward_period.dart::billingCyclePeriod` 的
`offset=0` 語意是「涵蓋今天的本期(尚未結束)」,信用卡帳單彙總卡片用的就是
這個語意。但對帳模式跟 BeeCount Cloud `compute_cycle_period_billing` 一樣,
`cycle_offset=0` 應該是「最近一次已結束的週期」(你要對的是已經收到的帳單,
不是還在累積中的本期)。這裡沒有改動 `billingCyclePeriod` 本身(帳單彙總卡片
還在用它),而是在對帳模式自己的語意層加一個 `-1` 位移,避免兩處呼叫端各自
土法重寫位移邏輯又不小心算錯。**日後如果要改動 `statementCyclePeriod` 的
位移常數,要同時檢查這裡的文件註解跟 `defaultDeferredPostingDate` 是否也要
跟著調。**

## 4. Repository 層:輕量寫入方法,不重用整包 `updateTransaction`

**改了什麼**:`TransactionRepository` 介面(`lib/data/repositories/transaction_repository.dart`)
新增 `setTransactionReconciled`、`setTransactionDeferredPosting`、
`clearReconciliationBatch` 三個方法。`local_transaction_repository.dart`
實作為單欄位 `TransactionsCompanion` 局部寫入(比照既有
`updateTransactionFields` 的 tri-state `d.Value` 寫法)。`local_repository.dart`
包一層 `changeTracker!.recordLedgerChange(...)`(比照 `updateTransaction`
wrapper 的既有模式)。`clearReconciliationBatch` 批次寫入但逐筆記變更——
先查一輪 syncId/ledgerId 再寫,寫入後照這份清單逐筆呼叫 `recordLedgerChange`。

**為什麼**:對帳清單裡「勾選確認」是高頻、單欄位的輕量操作,不需要走
`updateTransaction` 那個帶十幾個參數的整包更新路徑(也避免呼叫端要先湊齊
`type`/`amount`/`categoryId` 等其實沒變的欄位)。

## 5. 讀取:複用 `getAccountTransactions`,寬視窗 + Dart 端依歸屬日精確過濾

**改了什麼**:新增 `lib/providers/reconciliation_providers.dart`
`accountStatementTransactionsProvider`。查詢時用比目標週期前後各多一期的
寬視窗呼叫既有 `BaseRepository.getAccountTransactions`(信用卡帳單彙總卡片
同一個方法),再用 `effectiveDate()` 在 Dart 端精確過濾到目標週期;轉帳只收
「轉入成員帳戶」(排除轉出),對齊 BeeCount Cloud `get_account_statement` 的
`OR` 分支語意。

**為什麼**:「入帳歸屬日」是 `deferredPostingAt ?? happenedAt` 的 COALESCE
語意,直接在 SQL 層 `happenedAt BETWEEN` 查詢會漏掉「消費日在別期但延後入帳
日落在本期」的交易。單一帳單週期的交易量天然有限,沒必要為此新寫一個帶
COALESCE 的 SQL 查詢——寬視窗抓資料 + Dart 端精確過濾夠用,也不用改動既有
`getAccountTransactions` 的 SQL。

## 6. UI:`AccountReconciliationSection`,掛在信用卡帳戶詳情頁「交易明細」tab

**改了什麼**:新元件 `lib/widgets/biz/account_reconciliation_section.dart`
(收合式 `ExpansionTile`,標題旁帶 `已確認/總筆數` 小標籤,預設收合)。掛載於
`lib/pages/account/account_detail_page.dart::_buildTransactionsTab`,緊接在
既有帳單彙總卡片之後。清單每列:左側圓形確認勾選、分類/備註、日期、金額、
轉帳/回饋/已延後徽章、編輯鉛筆(開既有 `showTransactionDetailCard`)、
延後/取消延後按鈕(同一顆按鈕依 `deferredPostingAt` 是否有值切換行為——見
第 7 節)。右上角選單:新增遺漏的交易(開 `TransactionEditorPage`)、排序
切換、取消全部選取(二次確認 dialog)。

順手把帳單彙總卡片裡「對帳筆數」那行從假資料(`'${txs.length} / ${txs.length}'`,
恆等於「全部已確認」的佔位字串)改成用同一批已抓到的 `txs` 真實算
`reconciledAt != null` 的筆數(`account_detail_page.dart` 第 1283 行附近)。

**額外修的一個既有缺口**:`_buildTransactionsTab` 原本只認字面
`account.type == 'credit_card'`,但信用卡合併帳單主帳戶(`account_group`)
自己的 `type` 是 `'account_group'`——`accounts_page.dart` 的
`_viewAccountDetail` 對主帳戶卡片一樣會導到這個頁面,導致點開主帳戶本身
(而非底下的子卡)看到的是一般帳戶版面,帳單彙總卡片的 `children` 聚合邏輯
形同永遠用不上。這次把判斷式改成
`account.type == 'credit_card' || account.type == 'account_group'`,讓對帳
模式(以及既有的帳單彙總/紅利回饋卡片)在開主帳戶本身時也能正確顯示依卡
分組小計。

**為什麼**:讀端點設計上信用卡合併帳單群組(主帳戶 + 子卡)是對帳模式的
主要使用情境之一(見 BeeCount Cloud `get_account_statement` 的
`is_billing_root` 檢查同時接受 `account_group` 跟獨立信用卡),不修這個
分支條件的話,對帳模式在最常見的「查看主帳戶」路徑下永遠不會出現。

## 7. 延後入帳:入口收斂在對帳清單本身,不動一般記帳表單

**改了什麼**:原計畫要在 `TransactionEditorPage`/`TransactionEntryForm`/
`TransferForm` 加一個可選的「延後入帳日」欄位,讓一般編輯表單也能設定/清除
這個欄位。實作時改成更輕量的做法:對帳清單每列的「延後」按鈕本身就是
雙態的——`deferredPostingAt == null` 時點擊開日期選擇器設定;已經有值時
同一顆按鈕變成「取消延後」,點擊直接清空(不用二次選日期),跟左側確認
勾選按鈕「再點一次取消」同一種低摩擦互動。

**為什麼(權衡)**:`TransactionEntryForm`/`TransferForm` 是很重的三分頁
表單元件,加一個新欄位要同時改表單 State、`SharedEntryFields` 跨 tab
同步 typedef、存檔時的參數穿線,影響面遠大於對帳模式本身。延後入帳這個
欄位的「設定」「檢視」「清除」三個操作在對帳清單這個單一入口就能完整
覆蓋,沒有使用者需要「在一般記帳表單裡設定延後入帳日」的場景(這個欄位
的存在意義就是對帳流程本身)。BeeCount Cloud web 版之所以在編輯表單也開了
這個欄位,是因為它的「全域編輯彈窗」本來就是通用元件,順手加一個欄位成本
極低——App 端的對應元件沒有這個前提,所以刻意選了風險更低的範圍。

## 刻意排除的範圍

- **回饋規則合併顯示**:BeeCount Cloud web 版對帳清單裡,同一個
  `card_reward_rule` 這期入帳的多筆回饋交易會合併成一列(點開才展開明細)。
  App 端沒有 `card_reward_rule` 這個實體(CLAUDE.md 已記錄:
  recurring_rule/installment_plan/debt/tx_template/card_reward_rule/project
  是 Cloud/web 限定,App 端不存在),這次的回饋徽章只是「分類名稱等於
  `回饋金` 就標記」的簡化版,不做規則反查/合併/明細彈窗。要做完整版需要先
  把 `card_reward_rule` 整個實體(本地表 + 同步 + 規則管理 UI)搬到 App
  端,是一個獨立的大專案。
- **餘額調整**(`tx_type=adjustment`):BeeCount Cloud 文件裡對帳模式旁邊
  的另一個子功能(§2.10),語意是「直接把帳戶餘額修正到指定值,差額系統
  自動算成一筆交易」。這次使用者只要求對帳模式本身,沒有要求這個。
- **一般記帳表單裡的延後入帳欄位**:見第 7 節。

## Verification

- `dart run build_runner build --delete-conflicting-outputs`:通過,`db.g.dart`
  正確產生 `reconciledAt`/`deferredPostingAt` 欄位。
- `flutter analyze`:0 error(既有 835 條 info/warning 噪音跟這次改動無關,
  新增檔案本身 0 issue)。
- `flutter test`:734 個測試全過(1 個既有 skip,跟本次改動無關)。新增
  `test/sync/transaction_reconciliation_apply_test.dart`(3 個案例)。修正
  `test/data/sync_pull_errors_schema_test.dart` 硬編碼的
  `schemaVersion == 36` 斷言為 37。
- 手動驗證(模擬器/實機)待補:開一張已設定 `billingDay`/`paymentDueDay`
  的信用卡帳戶(或合併帳單主帳戶),在最近一次已結束的週期內記幾筆消費/
  一筆轉入轉帳/一筆分類為「回饋金」的收入,依 [實作計畫](../../.claude/plans)
  Verification 章節逐項核對——尤其是深色/淺色主題、zh-TW/en 語言切換、
  跨裝置同步(`reconciledAt`/`deferredPostingAt` partial update 不互相
  清空)這幾項自動化測試覆蓋不到的角度。
