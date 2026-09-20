# 專案「退款」分類顯示、首次同步消失、AI專案指定同步 三項修正

使用者回報一個場景牽出三個獨立問題：在「娛樂」專案內對一筆 surfshark 訂閱
（分類「應用軟體」）做退款，退款交易被歸在「退款」分類（income 類型，
+2,806）。

## 問題 1：專案詳情頁「退款」分類金額顯示 0.00

`_CategoryBudgetTile`（[lib/pages/project/project_detail_page.dart:698](../../lib/pages/project/project_detail_page.dart)）
只讀取並顯示 `usage.expenseTotal`，完全忽略 `usage.incomeTotal`。底層 SQL
（`LocalProjectRepository.getProjectCategoryBreakdown`）本來就有把
expense/income 分開累加，計算沒有錯；純退款分類的 `expenseTotal` 本來就是
0，於是畫面顯示 0.00，讓人以為退款金額不見了（專案總覽的「剩餘」數字其實
有正確加回退款，只是分類明細列顯示錯了）。

**修正**：改成顯示淨額 `netAmount = expenseTotal - incomeTotal`，依正負套用
`BeeTokens.expenseColor`/`incomeColor`（跟隨使用者在外觀設定裡的收支配色，
淨支出用支出色、淨收入/退款用收入色），同時把這個淨額也用在同一列的
`BudgetProgressBar`（原本進度條的 `used` 也只看 expenseTotal，有退款時進度
不會退回去）。

## 問題 2：首次同步後專案列表空白，要新增一筆交易才「長出來」

`ProjectOverviewPage` 讀的 `projectUsagesProvider`/
`allProjectUsagesIncludingDisabledProvider`（[lib/providers/project_providers.dart:13](../../lib/providers/project_providers.dart)）
是一次性 `FutureProvider`，只在 `projectRefreshProvider` 被 bump 時才重新
查詢——不像帳戶/分類列表用會自動反應 DB 寫入的 `StreamProvider`。而
`lib/providers/sync_providers.dart` 裡兩處同步完成後的刷新清單（自動 pull
的 `PullCompleted` handler，以及登入後首次 bootstrap 全量同步）都有 bump
`budgetRefreshProvider`，唯獨漏了 `projectRefreshProvider`。新增交易後畫面
會「自己長出來」，只是因為送出交易的流程剛好會 bump 這個 provider，純屬
巧合——編輯專案、編輯專案分類子預算也有一樣的副作用。

**修正**：在這兩處刷新清單都補上
`ref.read(projectRefreshProvider.notifier).state++`，跟 `budgetRefreshProvider`
並列。

## 問題 3：AI 記帳「AI專案指定」設定不跨裝置同步

這個設定（智慧記帳 → AI 記帳 → AI專案指定，`smartBillingProjectAssignModeProvider`，
[lib/providers/smart_billing_providers.dart](../../lib/providers/smart_billing_providers.dart)）
從新增以來就只存在本機 SharedPreferences，從未被納入
`AIProviderManager.snapshotForSync()`/`applyFromServer()`
（[lib/ai/providers/ai_provider_manager.dart](../../lib/ai/providers/ai_provider_manager.dart)）
的欄位清單——同一個機制已經在同步 AI 服務商設定、語音觸發方式等欄位，只是
這個較晚加入的設定沒被接進去。

**修正**：比照 `voice_trigger_mode` 的作法——
- `snapshotForSync()`：`prefs.containsKey(kAiProjectAssignModeKey)` 時才把值
  塞進 `project_assign_mode` 欄位（避免把沒設定過的裝置的預設值覆蓋掉別的
  裝置已同步好的設定）。
- `applyFromServer()`：讀回 `project_assign_mode`，寫回本機 prefs。
- UI 變更時（`smart_billing_page.dart` 的 `_showProjectAssignModeDialog`）
  額外呼叫 `AIProviderManager.onConfigChanged?.call()` 觸發推播——這個設定的
  持久化跟推播分屬兩個 provider/類別，原本只接了持久化，沒接推播那一段。
- server 拉回套用後（`sync_providers.dart` 的 `ProfileField.aiConfig` 分支），
  額外把新值同步進 `smartBillingProjectAssignModeProvider` 的 Riverpod state
  （直接賦值，不經過 UI 的 onChanged 路徑，避免推播回音）。

**不需要改 BeeCount Cloud**：`ai_config` 在雲端是不限欄位的 JSON blob
（`src/models.py` 的 `ai_config_json`，`src/schemas.py` 的 `ai_config: dict | None`），
新增 key 不用改 schema，這點在 `src/schemas.py` 的 `appearance`/`ai_config`
欄位註解裡本來就寫明是刻意設計。

## 問題 4（跨 repo，BeeCount Cloud）：網頁專案詳情頁「退款」分類整個消失

BeeCount Cloud（`/Users/andy/BeeCount-Cloud`，獨立 git repo）的
`get_project_breakdown`（`src/routers/read/ledgers.py`）從頭到尾只追蹤
expense 類型交易，跟 App 端的雙軌設計（expense/income 分開累加）不一致，
兩個過濾條件疊加導致「退款」這種純 income 分類整個從拆解列表消失，不是分頁
被截斷：

1. `spend_rows` 查詢原本 `tx_type == "expense"`，income 類型的分類金額從沒
   被彙總過。
2. `category_universe`（決定哪些分類會出現在畫面上）原本只用
   `kind == "expense"` 的一級分類作為基底，income 類型分類（如「退款」）
   若沒有專案子預算配置，永遠不會進入任一分組。

**修正**（範圍：只動「專案分類拆解」這個端點，不動頂層「預算 X/Y」bar 的
`spent`/`effective_budget` 分子邏輯——那個設計文件`docs/2026-09-06-project-category-budget-period-switch-design.md`
已明確寫成「income 只併入分母」，是刻意設計，這次不重新討論；也不動
`list_budget_usage` 這個非專案的一般預算用量端點，兩者是各自獨立的 D2 慣例
表面）：

- `src/routers/read/ledgers.py`：`spend_rows` 改成同時撈 expense/income 並依
  `(category_sync_id, tx_type)` 分組，彙總成 `(expense, income, count)` 三元
  組；`category_universe` 的基底分類改成涵蓋所有 kind 的一級分類（不再只挑
  expense kind），比照 App 端 `level1Categories` 不分收支的作法。
- `src/schemas.py` 的 `ReadProjectBreakdownCategoryOut` 新增 `income_spent`
  欄位；`spent` 語意不變（仍是純支出毛額）。
- 每個分類的 `progress_pct`（已分配分類的進度條）改用淨額
  `spent - income_spent` 計算，退款會把已用進度打回去，跟 App 端
  `_CategoryBudgetTile` 的 netAmount 口徑一致。
- 前端 `frontend/packages/api-client/src/types.ts` 的
  `ReadProjectBreakdownCategory` 型別、`frontend/apps/web/src/components/dialogs/ProjectDetailDialog.tsx`
  的三處分類列渲染點（`CategoryGroup` 的已分配/未分配列表、未設定預算的內
  聯區塊）都改成顯示 `spent - income_spent` 的淨額，並依正負套用
  `Amount` 元件既有的 `positive`/`negative` tone（跟隨站台的收支配色 CSS
  token，不用另外寫顏色）。

**測試**：`tests/test_project_breakdown.py` 新增兩個案例——純退款分類（無
支出交易）能出現在 `unallocated_categories` 並帶出正確的 `income_spent`；
同分類內支出退款金額相等時 `progress_pct` 算出 0 而不是用毛支出算出的
80%。原有 5 個測試全部維持通過。

**部署**：後端/前端都需要重新部署 BeeCount Cloud 才會生效，App 端三項修正
則隨下個 App 版本發布生效。

## 刻意不做的事

- 沒有動頂層「預算 X/Y」bar 的分子語意（是否該把退款/收入從已用金額裡扣
  掉）——這是文件明確寫過的既有設計選擇，牽動範圍更大（同時影響
  `list_budget_usage` 這個非專案端點的一致性），留待另外討論。
- 沒有處理「未設定預算」分類清單因為改成涵蓋所有 kind 而變長（原本薪水等
  income 分類即使從沒在任何專案用過也不會出現，現在會）——這是跟 App 端
  對齊後的自然結果，不是額外增加的行為。
