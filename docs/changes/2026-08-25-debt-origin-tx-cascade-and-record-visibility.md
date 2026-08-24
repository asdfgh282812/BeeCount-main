# 借還款:刪起點交易級聯刪欠款 + 欠款管理頁面補上「欠款紀錄」

日期:2026-08-25
背景:延續 `docs/changes/2026-08-21-debt-tracking.md` 以來的借還款功能,
使用者回報兩個落差:①刪除欠款的起點交易後,若這筆欠款還沒有任何還款記
錄,欠款管理頁面上會留下一筆找不到起點的空殼記錄,應該一併清掉;②欠款
管理頁面展開卡片時只找得到「還款紀錄」,找不到「欠款紀錄」(起點交易本
身)。App(本 repo)+ Server(`../BeeCount-Cloud`,獨立 repo)+ Web 三邊
都改了。

## 1. 刪起點交易級聯刪欠款

**判斷邏輯**(App/Server 共用同一條規則):一筆交易若是某筆欠款的起點交
易(`Debts.originTransactionSyncId` / server 端 `origin_tx_sync_id` 反查
命中),且該欠款目前沒有任何還款交易(`hasRepayments` 為 false),代表這
筆欠款已經沒有任何交易佐證(起點沒了、也沒還款),此時連同該欠款一併刪
除。這跟使用者主動刪欠款時的 `DEBT_HAS_REPAYMENTS` 守衛是同一條判斷邏
輯,只是反過來在刪交易時自動觸發——如果該欠款已經有還款記錄,則沿用既
有守衛,只刪交易、不動欠款,避免誤刪有記錄的欠款。

**App**:[local_repository.dart](lib/data/repositories/local/local_repository.dart)
的 `deleteTransaction`:刪除交易前後,額外用
`getDebtByOriginTransactionSyncId` 反查是否為某欠款的起點交易,命中且
`hasRepayments` 為 false 時呼叫既有的 `deleteDebt`(沿用它本來就有的
change-tracking 邏輯,不重複造輪子)。

**刷新 provider 的坑**:`debtsWithStatusProvider` 等欠款相關 provider 只
靠 `debtsRefreshProvider`(手動計數器)觸發重算(見
[debt_providers.dart](lib/providers/debt_providers.dart) 的既有文檔——
`remainingAmount`/`status` 跨表算,單純 watch `Debts` 表不會在交易變化時
重算),但刪交易的呼叫點分散在
[transaction_detail_card.dart](lib/widgets/biz/transaction_detail_card.dart)、
[transaction_list.dart](lib/widgets/biz/transaction_list.dart)、
[category_detail_page.dart](lib/pages/transaction/category_detail_page.dart)
(兩處)、[tag_detail_page.dart](lib/pages/tag/tag_detail_page.dart)、
[search_page.dart](lib/pages/transaction/search_page.dart) 共 6 個呼叫
點,這些呼叫點原本完全不知道欠款的存在。這次在每個呼叫點刪除交易後,跟
既有的 `statsRefreshProvider`/`budgetRefreshProvider` 一樣補上
`ref.read(debtsRefreshProvider.notifier).state++`——即使該次刪除跟欠款無
關,多刷新一次也無副作用,但漏掉任何一個呼叫點都會讓級聯刪除後的欠款管
理頁面停留在刪除前的快取畫面,直到下次手動觸發刷新。`sync_diff_service.dart`
的批量刪除 fallback 路徑(單筆同步失敗才會走到,屬於邊界情況)跟
`ai_chat_service.dart` 的「撤銷記帳」路徑沒有補這個刷新——底層 repository
的級聯刪除邏輯仍會正確執行,只是這兩個路徑觸發時欠款管理頁面通常不在畫
面上,即時刷新的必要性低,先不處理。

**Server**(`../BeeCount-Cloud`):交易刪除有兩條互相獨立的路徑,都要補:
- 單筆 `DELETE /ledgers/{id}/transactions/{tx_id}` 走
  `_commit_write_fast_tx` 的快路徑(跳過全量 snapshot build,直接動
  `read_tx_projection`),新增 `_cascade_delete_orphaned_origin_debt`
  helper(`src/routers/write/_shared.py`),在刪除交易的分支裡呼叫。
- 批量 `POST /transactions/batch/delete` 走
  `snapshot_mutator.delete_transaction`(逐筆 mutate 一份完整
  snapshot,靠 `_emit_entity_diffs` 對 `items`/`debts` 兩個列表分別
  diff 後自動產生對應的 SyncChange),在這個函式裡直接對 mutate 後的
  snapshot 補上同一條判斷邏輯——不需要額外處理 diff/emit,因為批量刪除
  端點本來就會對 `debts` 列表做 diff。
- MCP 的 `delete_transaction` 工具內部呼叫的正是上面的單筆 DELETE
  端點,不需要額外改動。
- App 自己的 sync push(刪交易 + 刪欠款各記一筆 change)走的是既有的
  `sync_applier.py` 通用 apply-change 邏輯,`transaction`/`debt` 兩個
  entity type 的 delete 早就支援,不需要新增邏輯——這次 server 端的改
  動只是補齊「web/MCP 直接呼叫 REST 刪交易」這條 App 本來就不會走的路
  徑,讓兩邊行為一致。

## 2. 欠款管理頁面補上「欠款紀錄」(起點交易)

之前展開一筆欠款卡片只看得到「還款紀錄」(`_RepaymentList`),起點交易本
身完全沒有入口——web 端的 `DebtsPanel.tsx` 也是同款落差(只渲染
`debt.repayments`)。

**Server**:`ReadDebtOut` 新增 `origin_transaction`
(`ReadDebtRepaymentOut | None`,跟既有的 `repayments` 同一個型別,只是
單筆而非陣列),`list_debts`(`src/routers/read/ledgers.py`)額外查一次
`origin_tx_sync_id` 對應的交易金額/日期填進去——找不到(欠款是 web 建
的、或起點交易已被刪除)就是 `None`。原本就有的 `origin_tx_id` 欄位維持
不變(純 syncId,沒有金額/日期)。

**App**:新增 `debtOriginTransactionProvider`
([debt_providers.dart](lib/providers/debt_providers.dart)),鍵是
`Debt.originTransactionSyncId`,底層直接複用既有的
`getTransactionBySyncId`。[debt_list_page.dart](lib/pages/debt/debt_list_page.dart)
展開卡片時,`originTransactionSyncId` 非 null 才渲染新的
`_OriginRecordSection`(標題「欠款紀錄」+ 日期/金額一行,樣式跟
`_RepaymentList` 的每一列一致);`_RepaymentList` 本身也順手補上「還款記
錄」小標題,讓兩個 section 並排時看得出區別(原本標題只在按鈕文字上,展
開後的內容本身沒有標題)。新增 l10n key `debtOriginRecordLabel`(只加
`app_en.arb`/`app_zh_TW.arb`,既有政策)。

**Web**:`ReadDebt` 型別(`packages/api-client/src/types.ts`)補上
`origin_transaction`,`DebtsPanel.tsx` 的 `DebtCard` 在既有的
「還款記錄」區塊之前加一個平行的「欠款紀錄」區塊,同樣支援
`onJumpToTx` 點擊跳轉(既有的 `onJumpToTx` 機制本來就是給
`repayments` 用的,這裡直接複用)。新增 i18n key
`debts.label.originTransaction`(en/zh-CN/zh-TW 三個既有語系檔都補)。

## 刻意不做的事

- 沒有讓 App 的「還款紀錄」列表變成可點擊跳轉交易詳情(對齐 web 既有的
  `onJumpToTx`)——這次只要求「找得到欠款紀錄」,不是要求兩邊點擊行為
  完全對齐,範圍之外的體驗加強留待之後有需要再做。
- 沒有處理「web/MCP 建立的欠款,原本就沒有起點交易」的情況——這種欠款
  `origin_tx_id`/`origin_transaction` 本來就是 `None`,App/Web 端只在非
  null 時才渲染 section,是預期行為不是 bug。
- 沒有改動 `deleteDebt` 本身的 `DEBT_HAS_REPAYMENTS` 守衛——這次是新增
  一條「反過來,刪交易時觸發」的路徑,原本「使用者主動刪欠款」那條路徑
  的行為完全不變。

## 相容性

Server 的 `origin_transaction` 是新增的唯讀欄位,舊版 App/Web 讀到會忽略
不影響;級聯刪除是新增的伺服器端行為,不改變既有 API 的 request/response
形狀,舊版 App/Web 呼叫這兩個既有刪除端點時行為不變(只是現在多了一個副
作用:命中條件時欠款會一併消失,這正是這次要修的行為,不是破壞性變更)。

## 測試

- **App**:`test/repositories/local/debt_repository_test.dart` 新增 3
  個案例(刪起點交易且無還款 → 欠款一併刪除;刪起點交易但已有還款 → 欠
  款保留;刪還款交易本身 → 不影響欠款)。`flutter analyze` 零錯誤,
  `flutter test`(repositories/data/sync 子目錄 + debt 相關 widget 測
  試)全過。UI 層(`_OriginRecordSection`)沒有新增 widget test,靠既有
  的 `debt_list_page.dart` 手動邏輯覆核 + `flutter analyze` 把關。
- **Server**:`tests/test_debts.py` 新增 5 個案例(`origin_transaction`
  在列表裡正確帶出/沒有起點交易時為 null、單筆 DELETE 級聯刪除欠款、有
  還款記錄時不誤刪、批量刪除同樣會級聯)。跑過
  `tests/test_debts.py`(35 個案例全過)+
  `tests/test_tx_batch_delete.py`/`test_installment_plans.py`/
  `test_account_cascade_delete.py`/`test_projection_consistency.py`/
  `test_shared_ledger_delete_cleanup.py`/`test_tx_splits.py`(既有交易刪
  除相關測試,確認沒有連帶破壞),以及全專案 `pytest`(除兩個跟這次改動
  無關的既有失敗案例——`test_import_simple.py::test_accounts_parent_before_child_required`
  跟 `test_recurring_rules.py::test_recurring_occurrence_update_overridden_skipped_by_update_from`,
  改動前就會失敗,已用 `git stash` 驗證過——其餘全過)。
- **Web**:`tsc -b apps/web --force`(monorepo project references,涵蓋
  `api-client`/`web-features`/`apps/web`)全量重建零錯誤,沒有起 dev
  server 手動點過 UI(無瀏覽器環境)。
