# AI 記帳專案指定邏輯

設計文件:`docs/superpowers/specs/2026-09-11-ai-billing-project-assignment-design.md`(實作完全依照該文件的三模式設計,以下記錄實際落地時的檔案異動與取捨)。

## 背景

AI 記帳(對話/拍照/語音/背景截圖/背景通知,5 個管道)原本完全不處理「專案」(`Projects`/`Transactions.projectSyncId`),AI 建立的交易永遠不帶專案。本次新增使用者可設定的三種模式:`none`(維持現狀)、`ask`(詢問使用者)、`aiDecide`(AI 自行判斷)。

## 入口

- **設定模式**:「我的」→「智能記帳」進入 `SmartBillingPage`,「智能記帳通用設置」卡片內新增一列(對應 `smartBillingProjectAssignMode` 標題),點擊彈出三選一 `RadioListTile` 對話框(不指定/詢問我/AI 自動判斷)。
- **待確認專案清單**:底部「專案」分頁(`ProjectOverviewPage`,`asTab: true`)——只有當前帳本存在待確認交易時,總預算區塊與專案列表之間會顯示待確認入口卡片(含筆數),點擊進入 `PendingProjectTransactionsPage` 逐筆補選。

## 檔案異動

### Layer 1(`lib/ai/`,不依賴 Repository/Riverpod/Drift)

- **`lib/ai/core/ai_project_assign_mode.dart`(新增)**:`AiProjectAssignMode` 列舉(`none`/`ask`/`aiDecide`)+ `kAiProjectAssignModeKey` SharedPreferences 鍵名常量。放在 Layer 1 是因為 `AiExtractionContext.forLedger` 與 Layer 2/應用層都要讀同一份鍵名,放這裡讓兩邊 import 同一個常量,不用各自硬編碼字串。
- **`lib/ai/core/ai_extraction_context.dart`**:新增 `AiProjectRef = ({String name, String syncId})` 型別 + `projects` 欄位。`forLedger()` 只有目前設定為 `aiDecide` 時才查詢「目前有效(`enabled=true`)」的專案清單(直接呼叫 `repository.getAllProjects(ledgerId)`,預設就是只回傳啟用中的);`none`/`ask` 模式維持空清單。
- **`lib/ai/core/bill_info.dart`**:新增 `project` 欄位(AI 猜測的專案名稱),`fromJson`/`toJson`/`copyWith`/`toString` 同步處理,容錯方式與既有 `tags` 欄位一致(缺欄位 = null)。
- **`lib/ai/core/prompt_builder.dart`**:新增 `{{PROJECTS}}` 占位符 + `_buildProjectHint()`。`ctx.projects` 為空時回傳空字串(零開銷,`none`/`ask` 模式下 prompt 完全不提「專案」這個欄位,不影響既有輸出格式);非空時才插入「11. project: ...」欄位說明 + 專案清單,並明確要求 AI「不確定或無明顯關聯就留空,不可虛構清單外的名稱」。已登記進 `PromptBuilder.placeholders`(`warnIfMissing: false`,因為這是全新的可選能力,絕大多數自訂模板用戶不會用到,不值得對他們跳警告)。

### Layer 2(`lib/services/billing/bill_creation_service.dart`)

新增 `ResolveMissingProject = Future<int?> Function(BillInfo bill)` 型別。跟 `ResolveMissingAccount` 的關鍵差異:**`null` 不代表取消**,而是使用者主動選擇「不指定專案」的正常完成(專案本來就是可選欄位),所以沒有對應的 `Skipped` 例外。

`createFromBill` 在帳戶比對完成、`repo.addTransaction(...)` 之前新增專案解析步驟(`_resolveProject`):

1. `none`:直接跳過,`projectSyncId=null`、`needsProjectAssignment=false`。
2. `aiDecide`:用 `BillInfo.project` 對「目前有效專案」做完全匹配 → 模糊匹配(`_matchProjectByName`,邏輯結構同 `_matchAccountByName`)。配對成功直接寫入,**不呼叫回調**。
3. 配對不到(或 `bill.project` 為空,或模式本來就是 `ask`):退回 `ask` 行為——有 `resolveMissingProject` 回調就呼叫;沒有(背景渠道)就標記 `needsProjectAssignment=true`,交易照常建立。

目前的 `AiProjectAssignMode` 直接讀 SharedPreferences(`_projectAssignMode()`),跟既有 `account_feature_enabled`/`smartBillingAutoTags` 的讀法一致,service 層不引入 Riverpod 依賴。

### `AiBookkeeper` / `AIChatService`

`fromText`/`fromImage`/`fromAudio`/`_persistAll`(`ai_bookkeeper.dart`)與 `processMessage`/`_handleTransaction`(`ai_chat_service.dart`)都新增 `resolveMissingProject` 參數,並排傳遞給 `resolveMissingAccount`,一路轉發到 `BillCreationService.createFromBill`。

### 三個互動管道

`ai_chat_page.dart`、`image_billing_helper.dart`、`voice_billing_helper.dart` 都新增 `resolveMissingProject: (bill) async { ...; final result = await ProjectPicker.show(context, ledgerId: ledgerId); return result?.project?.id; }`,寫法完全比照既有的 `resolveMissingAccount` → `AccountCardPicker.show()`。`ProjectPicker` widget 在本次之前就已存在(手動記帳表單「選擇專案」用),直接複用。

背景截圖監聽/背景通知監聽(`auto_billing_service.dart`)**沒有改動**——它們本來就不傳 `resolveMissingAccount`,新參數預設 `null` 一樣會自然落到 fallback 分支,標記 `needsProjectAssignment`。沒有像帳戶版那樣加「待確認專案」的推播通知文案(`autoBillingNotifyPendingAccountBody` 的姊妹版本),刻意縮小本次範圍;使用者仍能在專案總覽頁的入口卡片看到待確認筆數。

### 資料庫(`lib/data/db.dart`)

`schemaVersion` 58 → 59。`Transactions` 新增 `needsProjectAssignment`(`BoolColumn`,預設 `false`),完全比照 v40 `needsAccountAssignment` 的寫法與純本地語意(不同步,見 sync 段落)。Migration 用 `_addColumnIfMissing` 加欄,沒有動到其他表。

**連鎖影響**:`Transaction`(Drift 生成的資料類別)新增這個非空布林欄位後變成建構子必填參數,所有手寫 `Transaction(...)` 物件字面量(而非 `TransactionsCompanion`)都要補上 `needsProjectAssignment: false`——影響到 `local_tag_repository.dart`(`watchTransactionsByTag` 的原生 SQL 讀取路徑,改為多讀一欄 `needs_project_assignment`)、`widget_management_page.dart`(桌面 widget 預覽用的 `_sampleTransaction`),以及 6 個測試檔案(`recent_view_test.dart`/`dashboard_view_test.dart`/`card_reward_calc_test.dart`/`widget_preview_generator_test.dart`/`widget_render_harness_repro_test.dart`/`transaction_multi_currency_apply_test.dart`)。

### Repository 層

- **介面**(`transaction_repository.dart`):`addTransaction` 新增 `needsProjectAssignment` 參數;新增 `getTransactionsNeedingProjectAssignment(ledgerId)` 與 `setTransactionProjectAssignment({id, projectSyncId})` 兩個方法。
- **注意**:既有的 `setTransactionProjectLink({id, projectSyncId})` 是給**手動記帳表單**用的(不清除任何旗標);新的 `setTransactionProjectAssignment` 語意對齊 `setTransactionAccountAssignment`——寫入 `projectSyncId` **並清除** `needsProjectAssignment` 旗標。`projectSyncId=null` 代表明確選擇「不指定專案」,同樣算完成補選(跟 `ProjectPickResult` 的慣例一致)。
- **`LocalTransactionRepository`**:`addTransaction` 寫入新欄位;新增上述兩個方法的實作,查詢/寫入邏輯完全比照帳戶版。
- **`LocalRepository`**(組合層):`addTransaction` 轉發新參數;新增兩個方法的轉發實作,`setTransactionProjectAssignment` 寫入後一樣呼叫 `changeTracker.recordLedgerChange`(因為 `projectSyncId` 本身要同步)並在非 null 時觸發 `ProjectBudgetReminderService.checkAndNotify`(跟 `setTransactionProjectLink` 一致)。

### 「待確認專案」UI

完整比照「待確認帳戶」既有實作:

- **`lib/providers/pending_project_providers.dart`(新增)**:`pendingProjectRefreshProvider`(手動刷新計數器)+ `pendingProjectTransactionsProvider`(`FutureProvider.family<List<Transaction>, int>`)。
- **`lib/pages/project/pending_project_transactions_page.dart`(新增)**:清單頁,逐筆列出待確認交易,點擊彈出 `ProjectPicker.show()`。跟帳戶版的關鍵差異:`ProjectPicker.show()` 回傳 `null`(使用者滑動取消)要維持待確認狀態不動;回傳 `ProjectPickResult(null)`(明確選「不指定專案」)則要正常完成補選、清除旗標——兩者判斷邏輯不能合併成帳戶版那樣的單一 `result?.xxx == null` 判斷。
- **`project_overview_page.dart`**:新增 `_buildPendingProjectEntry()`,只有目前帳本存在待確認交易時才顯示入口卡片(含筆數),否則 `SizedBox.shrink()`,插入在總預算區塊與專案列表之間。

### 設定 UI(`smart_billing_page.dart` + `smart_billing_providers.dart`)

- `smartBillingProjectAssignModeProvider`(`StateProvider<AiProjectAssignMode>`,預設 `none`)+ `smartBillingProjectAssignModeInitProvider`(啟動時讀 SharedPreferences 灌值,並 `ref.listen` 寫回),寫法比照 `smartBillingAutoTagsProvider`/`InitProvider`,鍵名沿用 Layer 1 的 `kAiProjectAssignModeKey`。已掛進 `ui_state_providers.dart` 的啟動初始化 `Future.wait` 清單。
- `smart_billing_page.dart` 的「智能記帳通用設置」卡片新增一列,點擊彈出三選一 `RadioListTile` 對話框(比照既有 `_showVoiceTriggerDialog` 的寫法)。

### 本地化

`app_en.arb`/`app_zh_TW.arb` 新增:`smartBillingProjectAssignMode`、`aiProjectAssignModeNone(Desc)`/`Ask(Desc)`/`AiDecide(Desc)`、`pendingProjectPageTitle`/`EmptyMessage`/`EntryCardTitle`/`AssignSuccess`。依既有政策(見 memory)只維護這兩個 arb,未觸碰 `app_zh.arb`/`app_ko.arb`。

## Out of scope(同設計文件)

- 標籤自動指定邏輯不動。
- `aiDecide` 純文字語意比對,不納入專案預算用量。
- 手動記帳表單既有的專案欄位行為不動(仍用 `setTransactionProjectLink`)。
- CSV 匯入、週期性交易產生器不受影響。
- 背景渠道的「待確認專案」推播通知文案(帳戶版有,這次刻意不做對稱,避免範圍蔓延——見上方「三個互動管道」段落)。

## 測試

- `test/ai/core/ai_extraction_context_test.dart`:三模式下 `projects` 欄位行為(含封存專案不出現)。
- `test/ai/core/bill_info_test.dart`:`project` 欄位的 `fromJson` 解析。
- `test/services/billing/bill_creation_service_test.dart`:三模式分流的 8 個場景(none 略過、ask 有/無回調、ask 回傳 null 不是取消、aiDecide 完全匹配跳過回調、aiDecide 配對不到退回 ask、aiDecide 空值走 fallback)。
- `test/repositories/local/needs_project_assignment_test.dart`(新增,比照 `needs_account_assignment_test.dart`):`getTransactionsNeedingProjectAssignment`/`setTransactionProjectAssignment` 的 CRUD 正確性,含「不指定專案」也清旗標的場景。
- `flutter analyze` 無新增錯誤;`flutter test` 全量跑過(1253 個測試),僅 1 個與本次改動無關的既有失敗(`calendar_month_jump_test.dart`,在未改動的 `main` 分支上同樣失敗)。
