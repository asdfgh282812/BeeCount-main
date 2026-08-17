# 對帳模式三修:延後入帳跨期計算、群組子卡分組、取消對帳雙向同步失效

日期:2026-08-18
背景:延續同日稍早的 [對帳模式](2026-08-18-reconciliation-mode.md)、
[對帳模式拆頁與週期連動修正](2026-08-18-reconciliation-page-and-sync-fix.md)。
使用者這次帶了三張截圖(web 對帳彈窗、App 對帳頁當期/上期各一張),回報:
延後入帳的交易在 App 端沒有正確滾入新週期(仍卡在原週期,且顯示成「未延後」)、
信用卡群組(合併帳單)子卡在對帳清單裡沒有分組、以及「取消對帳確認」這個
動作不管在 App 或 web 哪一端做都同步不到另一端(但「確認」本身雙向都正常)。

## 1. 延後入帳跨期計算:過濾邏輯搬到 SQL 層,不再靠寬視窗猜

**根因**:`accountStatementTransactionsProvider`(`reconciliation_providers.dart`)
舊版做法是呼叫既有 `getAccountTransactions(startDate: prevCycle.start, endDate:
nextCycle.end)`——只抓「目前檢視週期」前後各多一期的寬視窗,查詢本身是照
`happened_at`(原始發生日)過濾,抓回來後才在 Dart 端用 `effectiveDate`
(`deferredPostingAt ?? happenedAt`)精確篩選。這在「延後剛好一期」時湊巧能動
(原始 `happened_at` 落在寬視窗內),但只要:

- 使用者透過日期選擇器手動選了超過一期以外的延後日(UI 本身允許選到 3 年後),或
- 延後距離造成原始 `happened_at` 落在寬視窗外,

SQL 查詢那層就直接抓不到這筆交易,Dart 端的 `effectiveDate` 過濾再精確也沒用
——資料根本沒被撈出來。使用者這次截圖裡兩筆「旅行」交易被 web 延後到下一期
(08 月),但 App 端當期(08/05–09/04)只看到另一張子卡的 3 筆(777 元),
這兩筆延後的交易還卡在舊週期(07/05–08/04)、且顯示的是「延後」按鈕(未延後
狀態)而不是「已延後」徽章——代表這兩筆交易在本地 Drift 裡 `deferredPostingAt`
其實有值,只是查詢層沒把它們正確歸類到新週期。

**改法**:新增 `AccountRepository.getAccountStatementTransactions`
([account_repository.dart](../../lib/data/repositories/account_repository.dart)
介面 + [local_account_repository.dart](../../lib/data/repositories/local/local_account_repository.dart)
實作 + [local_repository.dart](../../lib/data/repositories/local/local_repository.dart)
透傳),直接在 SQL 用 `COALESCE(deferred_posting_at, happened_at)` 當入帳歸屬日
過濾週期起訖,不論延後了幾期都能正確歸屬。member 帳戶判斷同時收斂成對帳清單
專用的口徑(expense/income 只認 `account_id`,transfer 只認 `to_account_id`,
其它 type 不收),取代原本 `getAccountTransactions` 的通用 flow 分支。
`reconciliation_providers.dart` 改呼叫這個新方法,拿掉 Dart 端的寬視窗 + 二次
過濾邏輯。`lib/utils/reconciliation.dart` 的 `effectiveDate` 函式保留(仍是
UI/其它地方判斷入帳歸屬日的共用定義),只是查詢路徑不再用它做主要過濾。

「已延後」徽章跟「取消延後」按鈕的 UI 邏輯本身在
[account_reconciliation_page.dart](../../lib/pages/account/account_reconciliation_page.dart)
`_StatementRow` 早就是對的(`tx.deferredPostingAt != null` 就顯示徽章、按鈕
文字跟行為互換)——這次沒有額外修改,問題全部出在查詢層撈不到資料。

## 2. 信用卡群組子卡分組展示

**改法**:`account_reconciliation_page.dart` 新增 `_buildRowsOrGroups`:單卡
帳戶(`widget.children` 空)維持原本平鋪清單;群組帳戶(有子帳戶)依
`_groupAccountId(tx)`(expense/income 看 `accountId`,transfer 看
`toAccountId`)把交易分桶到 `[account, ...children]` 各自的分組,每組上方
顯示卡片名稱 + 這期筆數 · 金額小計(`_buildGroupHeader`),比照 web 端
`AccountReconciliationSection.tsx` 的分組樣式(「大戶信用卡 2 · 78」)。小計
用 `groupTxs.fold(amount)` 加總原始金額(不套用 `signedStatementAmount` 的正負
號翻轉,web 端範例全是正值消費,這裡取一致的「金額量級」呈現)。空分組(該
子卡這期沒有交易)不佔位。

## 3. 取消對帳確認雙向同步失效:BeeCount Cloud `_merge_from_spec` 把顯式 null 當成缺鍵

依使用者這次列出的三個排查點逐一核對(BeeCount Cloud 是獨立 repo
`../BeeCount-Cloud/`):

**排查結論**:App 端(`entity_serializer.dart` 恒發 + `sync_engine_apply.dart`
`containsKey` 保護)跟 Cloud 端 web PATCH 快路徑
(`snapshot_mutator.py::update_transaction`)這兩條路徑的顯式 null 處理都是
**對的**——`update_transaction` 早就用 `"reconciled_at" in payload` 判斷,不是
`payload.get(...) is not None`。**真正的 bug 在第三條路徑**:mobile
`/sync/push` 的 projection apply(`../BeeCount-Cloud/src/sync_applier.py`
`_merge_from_spec`,被 `merge_with_existing`/`merge_with_existing_user` 呼叫,
這兩者是 `_LEDGER_MERGE_SPECS`/`_USER_MERGE_SPECS` 所有 entity 共用的合併函式)。

舊版寫法:
```python
return {**base, **{k: v for k, v in payload.items() if v is not None}}
```
`base` 是從 existing row 讀出來的舊值組成的 dict。這行只把 payload 裡「非
None」的鍵疊上去——**沒法區分「payload 沒帶這個 key(缺鍵,應該保留舊值)」
跟「payload 帶了這個 key 但值是顯式 None(使用者主動清空)」**,兩種情況在
這個 filter 底下都會被排除,顯式清空的值直接被過濾掉,`base` 裡的舊值原封
不動地穿透寫回 `read_tx_projection`。這條路徑正是 App 端「取消對帳確認」
(`reconciledAt: null`)透過 `/sync/push` 送出去時走的路,清空動作因此被
靜默吞掉——這解釋了 App 端清空但 web 讀不到清空結果的方向;web 端清空走的是
已確認正確的 PATCH 快路徑,理論上 App pull 應該收得到,使用者回報「雙向都
失效」可能是測試時剛好兩邊都先撞了 App→push 這條路(或 web 端另有別的呼叫
路徑最終也匯到同一個共用 merge 函式,沒有進一步深挖)。

**改法**(`../BeeCount-Cloud/src/sync_applier.py::_merge_from_spec`):改成按
`spec.fields` 逐欄位用 `payload_key in payload` 判斷是否覆蓋,對齊
`snapshot_mutator.py::update_transaction` 已經在用的寫法:
```python
merged: dict = {}
for spec_tuple in spec.fields:
    ...
    if payload_key in payload:
        merged[payload_key] = payload[payload_key]
    else:
        value = getattr(existing, db_attr)
        if transform is not None:
            value = transform(value)
        merged[payload_key] = value
return merged
```
這個函式是所有 ledger-scope / user-scope entity 共用的合併邏輯,不只修
`reconciledAt`/`deferredPostingAt`——凡是登記在 `_LEDGER_MERGE_SPECS`/
`_USER_MERGE_SPECS` 裡、且有「顯式清空」語意的欄位(例如 `refundOfId`),
mobile push 清空時之前都會撞到同一個 bug,這次一併修正。

新增 `../BeeCount-Cloud/tests/test_projection_consistency.py` 兩個回歸測試:
`test_mobile_push_clears_reconciled_at_to_null`、
`test_mobile_push_clears_deferred_posting_at_to_null`——先 push 帶值,再 push
一次「帶鍵但值是 null」的 payload,斷言 projection 真的變成 NULL,同時斷言
沒在第二次 payload 出現的欄位(缺鍵)維持舊值不受影響。修正前用這兩個測試
直接可重現 bug(用 `git stash` 只還原 `sync_applier.py` 重跑會失敗),修正後
連同 `test_projection_consistency.py` 全部 16 案例、以及 sync 相關測試檔
(`test_sync_concurrency.py` 等)都過。

**未修改**:`updated_at`/`SyncChange` 推進(使用者排查點 3)——已確認兩條
寫入路徑(web 快路徑、mobile push)都無條件建立 `SyncChange` row,沒有「值沒
變就跳過」的提前 return,不是問題所在。

## 4. 關閉按鈕行為

**結論:不用改**。對帳頁(`account_reconciliation_page.dart`)每個操作
(確認/取消確認/延後/取消延後)都是點擊當下立即呼叫
`repositoryProvider.setTransactionReconciled`/`setTransactionDeferredPosting`
寫本地 Drift,沒有「暫存,按確定才寫入」的草稿狀態——跟 web 端「完成對帳」
按鈕批次送出的互動模式不同,App 端每一次勾選本身就已經是最終寫入。頁面
頂部的關閉按鈕是共用元件 `PrimaryHeader` 的 `showBack`,`onPressed` 就是單純
`Navigator.of(context).maybePop()`(`lib/widgets/ui/primary_header.dart:110`),
沒有額外掛任何邏輯,也不需要——因為 `LocalRepository` 的寫入方法都會呼叫
`ChangeTracker.recordLedgerChange`,插入 `local_changes` 表的那一刻,
`SyncCoordinator`(`lib/cloud/sync/sync_coordinator.dart`)監聽這張表的
reactive stream,250ms 內 debounce 後呼叫 `engine.triggerAutoSync`,
`sync_engine_realtime.dart` 再 2 秒 debounce 後真正 push——這是跟頁面生命
週期完全獨立的全域機制,不管使用者是點右上角選單的「完成對帳」、按返回鍵、
或直接把 App 切到背景,只要寫入已經發生,大約 2.25 秒內就會自動觸發同步,
不需要在關閉按鈕上額外掛 hook。

## Verification

- App 端:`flutter analyze`(改動的 7 個檔案 0 issue,既有 info 級雜訊跟本次
  改動無關)、`flutter test`(734 個測試全過,含
  `test/sync/transaction_reconciliation_apply_test.dart`)。
- BeeCount Cloud:`pytest tests/test_projection_consistency.py`
  (16 案例全過,含新增的 2 個回歸測試)、`pytest tests/test_sync_concurrency.py
  tests/test_user_global_sync.py tests/test_sync_exclude_flags.py
  tests/test_account_hidden_sync.py tests/test_exchange_rate_sync.py
  tests/test_account_include_in_total_sync.py
  tests/test_account_swipesmart_card_id_sync.py
  tests/test_tx_account_syncid_fallback.py`(50 案例全過)。跑過全量
  `pytest tests/` 兩個既有失敗案例(`test_import_simple.py::
  test_accounts_parent_before_child_required`、`test_recurring_rules.py::
  test_recurring_occurrence_update_overridden_skipped_by_update_from`)用
  `git stash` 單獨還原 `sync_applier.py` 重跑後確認修改前就會失敗,跟這次
  改動無關,不在本次修復範圍內。
- 手動驗證待補:實機 + 雙端(App + web)對「取消對帳確認」「取消延後入帳」
  各自測一次雙向同步;群組帳戶對帳頁分組顯示;延後 2 期以上的交易正確歸類。
