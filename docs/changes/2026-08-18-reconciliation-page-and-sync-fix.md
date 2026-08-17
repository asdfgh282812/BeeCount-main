# 對帳模式:拆成獨立頁面 + 修正 Web 端對帳確認同步不到 App 的問題

日期:2026-08-18
背景:延續同日稍早的 [對帳模式(信用卡逐筆核對清單)](2026-08-18-reconciliation-mode.md)。
使用者回報兩個問題,附了兩張截圖:(1) 帳戶詳情頁最上方帳單彙總卡片跟下方
「對帳模式」區塊各自顯示不同週期(截圖裡上方是 `2026/08/05–09/04`,下方是
`2026/07/05–08/04`),畫面資訊脫鉤;(2) 在 BeeCount Cloud web 端完成對帳確認
(打勾)後,App 端執行同步,該筆交易仍顯示未確認。

## 1. 週期脫鉤的根因與修法:拿掉對帳模式自己的週期狀態

**根因**:`lib/utils/reconciliation.dart` 舊版 `statementCyclePeriod(billingDay,
cycleOffset)` = `billingCyclePeriod(billingDay, cycleOffset - 1)`,故意內部
多減 1,語意是「最近一次已結束的週期」;而帳單彙總卡片直接用
`billingCyclePeriod(billingDay, offset)`,offset=0 語意是「涵蓋今天的本期
(尚未結束)」。`AccountReconciliationSection`(舊版)自己維護一份獨立的
`_cycleOffset` State,預設 0 換算成的實際區間比帳單彙總卡片的預設區間早一期
——兩處預設值天生對不上,使用者切換其中一個的週期,另一個也不會跟著動。

**改法**:
- `lib/utils/reconciliation.dart`:刪掉 `statementCyclePeriod`,
  `defaultDeferredPostingDate` 改直接用 `billingCyclePeriod`。對帳模式不再有
  自己的週期語意層。
- `lib/providers/reconciliation_providers.dart`:`accountStatementTransactionsProvider`
  的 `cycleOffset`/`billingDay` 參數改成跟帳單彙總卡片同一套
  `billingCyclePeriod` offset(不再內部多減 1),呼叫端必須直接傳帳單彙總
  卡片目前選取的 offset。
- `lib/pages/account/account_detail_page.dart`:呼叫 `AccountReconciliationSection`
  時新增 `cycleOffset: _billingPeriodOffset`——這個 state 變數本來就是帳單
  彙總卡片自己的週期導覽狀態,現在直接餵給對帳模式,達成單一資料來源。使用者
  在帳單彙總卡片按上一期/下一期時,`_billingPeriodOffset` 變了,整個 widget
  tree 重建,`AccountReconciliationSection` 收到新的 `cycleOffset`,Riverpod
  family provider 的 key 跟著變,自動重新查詢——不用額外接線就做到「即時
  連動」。

## 2. UI:對帳模式拆成獨立頁面,帳戶詳情頁只留入口列

**改了什麼**:
- `lib/widgets/biz/account_reconciliation_section.dart` 從收合式
  `ExpansionTile`(內含週期導覽列、統計列、逐筆清單、選單)簡化成一個純入口
  列——標題「對帳模式」+ 已確認/總筆數徽章 + chevron,點擊用
  `Navigator.push` 開新頁 `AccountReconciliationPage`。不再有 `_cycleOffset`/
  `_sortDesc` 這些 State,整個 widget 改成 `ConsumerWidget`(無狀態)。
- 新增 `lib/pages/account/account_reconciliation_page.dart`:原本
  `ExpansionTile` 展開內容(週期文字、統計四列、逐筆 `_StatementRow` 清單、
  右上角選單:新增遺漏交易/排序/清除全部)整包搬過來,用 `PrimaryHeader`
  (`showBack: true`)當頁面標題列,選單移到 header 的 `actions`。**沒有**
  上一期/下一期切換——`cycleOffset` 是建構子參數,頁面存續期間固定不變,要
  換週期得先回上一頁在帳單彙總卡片切換,再重新點進來(呼應「移除內部切換
  列」的需求)。

**為什麼拆成獨立頁面而不是原地簡化**:使用者明確要求「對帳模式另開一個新
頁面,不要寫在同一個頁面」。額外好處:對帳清單本來就是這個信用卡帳戶頁面裡
最重的一塊(逐筆勾選 + 編輯 + 延後入帳三種互動),拆出去後帳戶詳情頁「交易
明細」tab 的 `ListView` 變輕,也讓對帳模式有自己完整的頁面寬度可以排版,不用
再塞在 `ExpansionTile` 的收合空間裡。

**避免循環 import**:`AccountReconciliationPage` 需要在確認/延後之後順便讓
帳單彙總卡片的「對帳筆數」行(`accountBillingPeriodTransactionsProvider`,
定義在 `account_detail_page.dart`)失效,但這個 provider 定義在頁面檔案裡,
如果對帳頁直接 import 回 `account_detail_page.dart`,會形成
`account_detail_page.dart → biz.dart → account_reconciliation_section.dart →
account_reconciliation_page.dart → account_detail_page.dart` 的循環。改法:
`AccountReconciliationSection` 新增一個 `onReturn` 回呼參數,`Navigator.push`
返回後除了讓自己的 `accountStatementTransactionsProvider` 失效,也呼叫
`onReturn`;`account_detail_page.dart` 呼叫端把
`() => ref.invalidate(accountBillingPeriodTransactionsProvider)` 傳進去。
`AccountReconciliationPage` 本身完全不 import `account_detail_page.dart`。

## 3. Web 端對帳確認同步不到 App:排查結論——不是資料契約 bug,是 App 端 UI 沒監聽同步代數

依使用者回報的四個排查方向逐一核對(BeeCount Cloud 是獨立 repo
`../BeeCount-Cloud/`,以下三點是唯讀排查,沒有在那個 repo 做修改):

1. **增量同步(updated_at/sync_seq)**:BeeCount Cloud 的增量同步不是靠
   `updated_at` 時間戳比對,是靠單調遞增的 `SyncChange.change_id` +
   `sync_cursors` 表(`src/routers/sync/pull.py`)——每次 `PATCH
   /ledgers/{id}/transactions/{tx_id}`(`src/routers/write/transactions.py::update_tx`
   → `_shared.py::_commit_write_fast_tx`)都會無條件寫一筆新的 `SyncChange`
   row(`payload_json=new_item`),不會因為「這次只改了 reconciled_at」就跳過
   ——這條路徑是所有交易欄位更新共用的同一個 fast path,不是 reconciled_at
   專屬邏輯,原本就沒有被略過的空間。**結論:此路徑正常,未發現問題。**
2. **欄位反序列化對齊**:App 端 `entity_serializer.dart`(push,序列化
   `reconciledAt`/`deferredPostingAt` 恆發、UTC ISO8601)與
   `sync_engine_apply.dart`(pull apply,`containsKey('reconciledAt')` 判斷
   缺鍵保留 vs 顯式清空)已在同日稍早的
   [對帳模式(信用卡逐筆核對清單)](2026-08-18-reconciliation-mode.md#2-sync-同步契約恆發語意不是有值才發)
   做完,並有 `test/sync/transaction_reconciliation_apply_test.dart` 三個案例
   覆蓋。Cloud 端 `snapshot_mutator.py::update_transaction` 跟
   `_shared.py::_projection_row_to_tx_dict`(fast path 的 `prev_item` 建構)
   都用同一套「有帶鍵才動、值 None 才清空 key、非 None 才寫值」邏輯,camelCase
   鍵名(`reconciledAt`/`deferredPostingAt`)兩端一致。**結論:欄位契約正確,
   兩端已對齊。**
3. **下行寫入邏輯**:`sync_engine_apply.dart::_applyTransactionChange`
   (第 260-333 行)已正確把 `reconciledAt`/`deferredPostingAt` 寫進
   `TransactionsCompanion`(insert 跟 update 兩條路徑都有)。**結論:正確,
   未發現問題。**
4. **UI 響應更新(Reactivity)——這裡才是實際的 bug**:對帳模式讀資料用的
   `accountStatementTransactionsProvider`(`reconciliation_providers.dart`)
   跟帳單彙總卡片用的 `accountBillingPeriodTransactionsProvider`
   (`account_detail_page.dart`)都是 `FutureProvider.family.autoDispose`,
   一次性查詢、Riverpod 不會自動重跑——`lib/providers/sync_providers.dart`
   裡已經有現成機制專門處理這個情境:`syncGenerationProvider` 這個計數器在
   `PullCompleted(applied>0)` 時 `+1`(見同檔案第 219-249 行的 `eventSub`
   listener),`categoriesProvider`/`accountByIdProvider`
   等既有 provider 都用 `ref.watch(syncGenerationProvider)` 讓自己在遠端
   pull 完之後重算——但對帳模式跟帳單彙總卡片這兩個 provider 建立時漏掉了
   這一行,所以 web 對帳確認的 `reconciledAt` 確實有正確 pull 下來寫進本地
   Drift(第 1-3 點都對),只是這兩個畫面的 `FutureProvider` 不知道要重新
   查詢,UI 停留在 pull 之前的舊快取上,使用者要手動離開再進來這個頁面
   (provider 因 `autoDispose` 被清掉重建)才會看到最新狀態。

**改法**:兩個 provider 都加一行 `ref.watch(syncGenerationProvider);`——
`reconciliation_providers.dart::accountStatementTransactionsProvider` 和
`account_detail_page.dart::accountBillingPeriodTransactionsProvider`。

## Verification

- `flutter analyze`:0 error(新增/改動的檔案本身 0 issue;既有 835 條
  info/warning 噪音跟這次改動無關)。
- `flutter test`:734 個測試全過(跟修改前基準一致),含
  `test/sync/transaction_reconciliation_apply_test.dart` 三案例、
  `test/data/sync_pull_errors_schema_test.dart`。
- 手動驗證待補:(a) 帳戶詳情頁切換帳單彙總卡片週期時,對帳模式入口列的
  已確認/總筆數徽章即時跟著變;(b) 點入對帳模式頁面沒有上一期/下一期按鈕,
  標題副標的週期文字跟帳單彙總卡片一致;(c) 在對帳頁勾選確認/取消,回上一頁
  後帳單彙總卡片的「對帳筆數」行也更新;(d) 雙端環境下,web 對帳確認後 App
  背景 pull 完成(或下拉手動同步)不用重進頁面就能看到已確認徽章更新
  ——這一項是這次要修的核心症狀,需要實機 + BeeCount Cloud 測試環境驗證。
