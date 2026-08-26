# 專案功能 Phase 1：資料模型 + 遷移 + 同步基礎

日期：2026-08-27

## 做了什麼

- 新增 `Projects` Drift 表（schemaVersion 43→44）+ `Transactions.projectSyncId`
  欄位，對齐 BeeCount Cloud 既有的 `project` sync entity。
- `ProjectRepository` / `LocalProjectRepository`：CRUD + 軟/硬刪除規則
  （有交易關聯→封存，沒有→硬刪，對齐 server）。`hasTransactions` 方法命名
  為 `projectHasTransactions`，避免跟既有 `AccountRepository.hasTransactions
  (int)` 在 `BaseRepository` 組合時撞名。
- `project` entity type 全流程 push/pull（`entity_serializer.dart` /
  `sync_engine_apply.dart` / `sync_engine_serialization.dart`）。交易的
  `setTransactionDebtLink` 旁新增對應的 `setTransactionProjectLink`（既有
  交易改連結走專用方法，不塞進通用 `updateTransaction`，維持既有分工）。
- `ProjectMigrationService`：app 升級時一次性把既有分類預算轉成專案，並
  回填該分類全部歷史支出交易的 `projectSyncId`（批次 500 筆，避免鎖表）。
  總預算（`type='total'`）不受影響——維持獨立於專案之外，語意詳見
  `docs/superpowers/specs/2026-08-27-project-feature-design.md` §0。

## 跟原設計文件的差異

- `Transactions` 對專案的關聯欄位命名為 `projectSyncId`（直接存 Project 的
  syncId 字串），不是原設計文件寫的「本地 int + resolver」——翻現有程式碼
  發現 `debtSyncId`/`recurringRuleId`/`refundOfSyncId` 都是同一套「存對方
  syncId」模式，這次照既有慣例走，因此完全不需要碰
  `sync_engine_resolvers.dart`。
- 遷移邏輯改用 `BudgetRepository.getAllBudgets()` 自行篩 `type='category'`，
  而不是 `getCategoryBudgets()`——後者只回傳 `enabled=true` 的列（給既有
  「分類預算」UI 用），會漏掉使用者已經封存的分類預算，導致這批資料完全
  不會被遷移。這是實作過程中測試發現的問題，修在
  `lib/services/data/project_migration_service.dart`。

## 刻意排除（本 phase 範圍外）

- 沒有任何 UI（總覽頁/編輯頁/記帳表單專案選擇器/首頁卡片/桌面 widget）—
  Phase 2-4。
- 沒有花費/進度/carryover 的計算邏輯——留給 UI 層需要時才加（Phase 2/3）。
- 舊分類預算相關 UI（`CategoryBudgetTile` 等）尚未移除，因為使用者升級後
  資料已經轉走，UI 暫時會顯示「沒有分類預算」的空狀態，不影響功能；正式
  清理排在 Phase 5。

## 驗證

- `flutter analyze`：全專案 0 error（837 個既有 info/warning，與本次改動
  無關）。
- `flutter test`：全專案 851 個測試全綠，含本次新增的三個測試檔案
  （`test/repositories/local/project_repository_test.dart`、
  `test/sync/project_apply_test.dart`、
  `test/services/data/project_migration_service_test.dart`）。
- **未做**：在真機/模擬器上實際跑一次「舊版資料庫（含分類預算資料）→
  升級到本版」的互動式驗證。自動化測試已經覆蓋 migration 的核心邏輯
  （分類/總預算區分、歷史回填範圍、冪等性、封存狀態轉移），但實機的
  DB 檔案升級路徑（SQLite ALTER 的實際執行、App 啟動時序）建議在正式
  發版前另外手動跑一次確認。
