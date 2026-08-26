# 專案功能 Phase 2+3:記帳表單整合 + 總覽/編輯/詳情頁 UI

日期：2026-08-27

承接 [Phase 1](2026-08-27-project-feature-phase1.md)（資料模型/遷移/同步基礎）。這次補上使用者真正能看到、能操作的 UI，也是本功能第一次有可進入的入口。

## 做了什麼

### Phase 2：記帳表單整合（design doc §6）

- `ProjectPicker`（[project_picker.dart](../../lib/widgets/biz/project_picker.dart)）：比照 `AccountCardPicker` 的 tap-to-pop bottom sheet，單選、可留空，多一個「不指定專案」列代表明確清空。
- `TransactionEntryForm` 新增「專案」欄位（帳本完全沒有專案時整列隱藏，不提供從表單直接建專案的入口）。`editingTransactionId` 非 null 時透過 `initialProjectSyncId` 非同步反查 `Project` 顯示——專案只存 syncId（同 `debtSyncId` 模式），沒有本地 int FK 可以同步回顯。
- 切 expense/income tab 時，專案選擇透過 `SharedEntryFields.projectSyncId` 同步，比照 `accountId` 的「null 不覆蓋」慣例。
- 既有交易改連結走專用 `setTransactionProjectLink`（不塞進通用 `updateTransaction`，同 `debtSyncId` 既有分工）；新增交易透過 `addTransaction(projectSyncId:)` 直接帶入。
- `TransactionEditUtils.editTransaction`/`copyTransaction` 透传 `transaction.projectSyncId`；`refundTransaction` 刻意不帶（同它本來就不帶 `category` 的既有邏輯）。
- 週期性交易（`recurringDraft`）刻意不轉發專案關聯，同 `splits` 目前的先例——recurring rule 的 `projectId` 關聯本次範圍外（design doc §11）。

### Phase 3：總覽/編輯/詳情頁（design doc §7-§8）

- `ProjectRepository`/`LocalProjectRepository` 補上花費/週期統計（`ProjectUsage`/`ProjectWithUsage`/`getProjectUsage`/`getAllProjectUsages`），Phase 1 只做了資料模型，這塊當時刻意留到 UI 層需要時才加：
  - `monthly` 跟隨帳本 `monthStartDay`（同 `BudgetRepository.getBudgetUsage` 口徑）；`yearly` 用自然年（不跟隨 `monthStartDay`，design doc 未特別要求）；`fixed` 用專案自帶的 `periodStart`/`periodEnd`。
  - `carryoverEnabled` 只結轉「上一期」一次，不做多期遞迴結轉；`fixed` 週期沒有「上一期」概念，即使開關開著也不生效。
- `lib/pages/project/`：
  - `project_overview_page.dart`：取代 `BudgetPage` 作為新的功能入口。頂部沿用總預算長條（`type='total'`，語意獨立於專案標記之外——design doc §0 決策 2，不受影響），下方是專案卡片列表（進度條/花費/剩餘/週期文字/封存徽章），右上角可切換「顯示已封存」。
  - `project_edit_page.dart`：名稱、icon（複用抽出來的 `GroupedIconGrid`）、預算金額/純記錄開關、週期類型（monthly/yearly/fixed，fixed 顯示起訖日期）、carryover 開關（fixed 時停用）、顯示於首頁開關、（編輯模式）啟用/封存開關。刪除規則對齐 §7/§8：先查 `projectHasTransactions` 決定提示文案，實際刪除都呼叫 `deleteProject`（repo 內部已經會自動判斷封存 vs 硬刪）。
  - `project_detail_page.dart`：完整統計卡片 + 該專案的交易列表（新增 `TransactionRepository.getTransactionsByProject`，同 `getRefundsOf` 的 syncId 過濾模式）。
- 導覽重新指向：`home_page.dart`、`home_budget_summary.dart`、`ledgers_page_new.dart`（長按帳本選單）、`app.dart`（桌面 widget deep link `page=budget`，wire 字串維持不動，只換落地頁）這 4 個原本 push `BudgetPage` 的地方都改成 `ProjectOverviewPage`。

### 共用元件抽取

- `GroupedIconGrid`（[grouped_icon_grid.dart](../../lib/widgets/biz/grouped_icon_grid.dart)）：從 `category_edit_page.dart` 私有的 `_GroupedIconGrid` 抽出來變成公開元件，`category_edit_page.dart` 改為 import 使用，行為不變。專案圖示固定用 `kind: 'expense'` 的圖示集（項目類型比分類更泛用，選較大的那組）。

## 跟原設計文件的差異 / 刻意簡化

- **拖曳重新排序未做**：design doc §7 提到專案卡片可拖曳重新排序（寫回 `sortOrder`）。這次先不做——`sortOrder` 在建立時遞增即可維持穩定順序，拖曳排序是可後補的體驗優化，不影響功能可用性。
- **`GroupedIconGrid` 的 `kind` 只有 `expense`/`income` 兩組**，專案不屬於任一邊，這次固定傳 `'expense'`（圖示集較泛用）。之後如果要專門為專案準備一組圖示,可以再擴充。
- **首頁卡片/原生桌面 widget 沒有跟著改版**：design doc §9 明確排在 Phase 4，這次只是把既有導覽入口（`home_budget_summary.dart` 點擊後的落地頁、桌面 widget 的 deep link）換成新的 `ProjectOverviewPage`，卡片本身的視覺內容（目前還是純總預算長條）沒有變。
- **`ledgers_page_new.dart` 的選單項目文字**從「預算管理」改成 `l10n.projectOverviewTitle`（「專案」），圖示從 `Icons.pie_chart_outline_rounded` 換成 `Icons.folder_outlined`；對應的 `budgetManagement`/`budgetManagementDesc` l10n key 沒有刪除或改名（`budgetManagementDesc` 目前程式碼裡沒有任何呼叫點，是既有的死 key，不在本次清理範圍）。

## 刻意排除（本次範圍外，留給後續 phase）

- Phase 4：首頁卡片改版（多專案進度環）、原生桌面 widget 改版（`lib/widget/views/budget_view.dart`）。
- Phase 5：舊分類預算 UI 清理（`CategoryBudgetTile`、`categoryBudgetsProvider`、`lib/pages/budget/budget_page.dart` 等——`budget_page.dart` 現在已經沒有任何導覽入口指向它，成為死碼，但檔案本身還在，留給 Phase 5 統一清理）、本地化補完（本次已加 `app_en.arb`/`app_zh_TW.arb` 的新 key）、文件更新（`docs/CLOUD_SYNC_INTEGRATION.md`）。

## 驗證

- `flutter analyze`：全專案 0 error。
- `flutter test`：全專案測試綠燈（詳見對應 commit）。
- **未做**：實機/模擬器上手動走一遍「記帳選專案 → 專案總覽看到卡片 → 進詳情頁看交易列表 → 編輯/封存/刪除專案」的完整互動流程。建議正式發版前手動跑一次，尤其是 `GroupedIconGrid` 抽取後 category 編輯頁的圖示選擇要重新確認一次沒有跑版。
