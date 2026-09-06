# 專案詳情頁分類子預算 + 期間切換

日期:2026-09-06
對應設計文件:`docs/superpowers/specs/2026-09-06-project-category-budget-period-switch-design.md`

比照 Moze 的三層預算模型,幫「專案」功能補上分類子預算(一級分類)、期間
切換(月/年/固定區間)、分類拆解統計畫面,以及每日預算/收入併入預算/預算
超標本機推播三個附加設定。以下依變動區塊分節說明,設計理由/範圍決策已在
spec 文件寫清楚,這裡只記錄跟 spec 字面描述有出入、或執行時才確定下來的
實作細節。

## 1. 資料層(schemaVersion 56)

- `lib/data/db.dart`:`Projects` 新增 5 欄(`incomeIncludedInBudget`/
  `dailyBudgetEnabled`/`dailyBudgetMode`/`reminderThresholdPercent`/
  `reminderNotifiedPeriodKey`,最後一個本機專用不進同步)+ 新表
  `ProjectCategoryBudgets`(`projectId`+`categoryId` 唯一索引)。沿用
  `_addColumnIfMissing`/`_createTableIfMissing` 既有 migration 慣例,
  `onCreate` 也補建了新索引(否則全新安裝會漏掉,同 v48/v49 索引的既有
  教訓)。
- `project_repository.dart`/`local_project_repository.dart`:`ProjectUsage`
  新增 `incomeIncluded` 欄位(`effectiveBudget` = budget + carriedOver +
  incomeIncluded);新增 `ProjectCategoryUsage`、`getProjectCategoryBreakdown`
  (raw SQL,`GROUP BY category_id` 一次查出 expense/income 分開加總)、
  `upsertProjectCategoryBudget`/`removeProjectCategoryBudget`/
  `getProjectCategoryBudgets`。
- `getTransactionsByProject` 加了可選 `start`/`end` 參數(都不傳維持全時間
  範圍,不破壞其它呼叫點)。

## 2. Cloud 同步契約(App 端定義完成,Cloud 端後續實作)

- `Projects` 新 4 欄(不含 `reminderNotifiedPeriodKey`)加進
  `serializeProject`/`_applyProjectChange`。
- 新 entity type `project_category_budget`:`entity_serializer.dart` 新增
  `serializeProjectCategoryBudget`、`sync_engine_serialization.dart` 新增
  push case + fullPush 區塊、`sync_engine_apply.dart` 新增 apply case +
  `_applyProjectCategoryBudgetChange`、`sync_engine_resolvers.dart` 新增
  `_resolveProjectIdBySyncId`、`LookupCache` 加了 `_project` 這個 slot(跟
  ledger/category/account/tag 同款 prime + get/put)。

**跟 spec 字面描述有出入的地方**:`_applyProjectChange` 對其它舊欄位是
「無條件覆蓋,缺鍵視為清空」(`serializeProject` 恆發全量欄位,假設 Cloud
永遠回送完整 payload)。但這次新增的 4 個欄位改用 `containsKey` 保護——因為
Cloud 端目前完全不認得這 4 個 key,任何一次由 Cloud 廣播回來的 project 變
更(哪怕只是改了 name 之類的舊欄位)payload 都不會帶這 4 個 key。如果沿用
舊欄位「缺鍵=清空」的邏輯,本機剛設置好的這些設定會被下一次 pull 打回預
設值,直接違反 spec §0 第 5 點「本機優先寫入,多裝置間暫不同步」的過渡期
承諾。`_applyProjectChange` 函式頂部加了註解說明這個刻意的風格不一致,避免
未來有人「統一風格」時誤刪這個保護。`test/sync/project_partial_update_apply_test.dart`
直接釘住這個行為。

`project_category_budget` 本身維持跟 `serializeDebt`/`serializeProject` 一樣
的全量恆發風格(這張表沒有「清空代表特殊語意」的欄位),不需要 containsKey
保護。

## 3. 期間切換的 anchor 計算(跟 spec §4.3 字面描述的差異)

spec §4.3 原文寫「monthly:往回位移 offset 個月」,字面上像是直接對
`DateTime.now()` 做 `month - offset`。但實測這樣做在月底日期會有進位 bug:
例如 3/31 往回位移 1 個月,`DateTime(year, 2, 31)` 會被 Dart 自動正規化成
3/3,結果還是落在原本那個月,而不是二月。

`lib/providers/project_providers.dart` 的 `_projectPeriodAnchor` 改用
`month_range.dart` 的 `labelForDate`/`periodForLabel`(day=1 的 label 錨點)
计算,跟 `local_project_repository.dart` 的 `_previousPeriodRange` 是同一套
已驗證過的手法,不會有這個邊界問題。yearly 固定用年中日期(7/1)完全迴避
這類邊界。

## 4. UI

- `lib/widgets/ui/period_range_selector.dart`(新檔):`PeriodRangeSelector`
  (chevron + 可點擊文字)+ `showPeriodRangeListPicker`(選擇區間 bottom
  sheet,monthly/yearly 各往回列 12 期)。
- `lib/providers/project_providers.dart` 新增 `projectPeriodOffsetProvider`
  (`StateNotifier<Map<int,int>>`)+ `projectDetailDataProvider`(聚合
  project/usage/breakdown/categoryBudgets/allCategories 給詳情頁用,取代
  舊的固定 `DateTime.now()` 路徑;`projectUsageProvider` 保留給仍只需要
  「當期」的其它呼叫端)。
- `lib/pages/project/project_detail_page.dart` 重寫:期間切換列(fixed 週期
  隱藏,顯示靜態起訖日文字)+ 出帳/入帳/總計統計條 + 專案預算卡片(含未分配/
  超額分配、每日預算數字)+ 已分配/未分配/未設定 三組分類卡片(判斷順序:
  先看本期有沒有交易,沒有一律歸「未設定」;有交易才看有沒有分配)+ 點分類
  卡片鑽入該分類該期間的交易明細(前端過濾 categoryId,不擴充 repository
  簽章,同 spec §4 決策)。
- `lib/pages/project/project_category_budget_edit_page.dart`(新頁面):列出
  一級分類,逐列「設定子預算」開關 + 固定金額/按照比例切換,頁尾顯示
  已分配/總預算(超額不擋存檔)。
- `lib/pages/project/project_edit_page.dart` 新增第 5 個 SectionCard:收入
  併入預算/每日預算(固定/比例)/預算提醒(50/80/100/120 常見預設 + 自訂
  輸入)。

## 5. 本機通知(預算超標提醒)

`lib/services/system/project_budget_reminder_service.dart`(新檔):走本機
通知而非 Cloud 通知中心(理由見 spec §6.3——通知中心只對 BeeCount Cloud 用
戶生效)。通知文案直接寫死中文,不走 l10n——這是沿用同層
`CreditCardReminderService` 的既有慣例(這個 codebase 的本機推播目前都沒有
走 l10n,不在這次順手改動範圍內)。

觸發點掛在 `lib/data/repositories/local/local_repository.dart` 的
`addTransaction`/`updateTransaction`/`setTransactionProjectLink` 三處寫入
完成後(非同步、不擋交易寫入本身),條件是該筆交易帶有 `projectSyncId`。
`updateTransaction` 沒有 `projectSyncId` 參數(專案連結是透過獨立的
`setTransactionProjectLink` 設定),所以這裡改用寫入前查到的舊交易
`old.projectSyncId` 判斷是否要重新檢查(修改金額也可能讓已掛專案的交易超
標)。

## 6. l10n

依 `feedback_l10n_policy_change` 只維護 `app_en.arb` + `app_zh_TW.arb`。新增
的 key 都遵循既有 `project<Area><Thing>` 命名慣例。

## 驗證

- `dart run build_runner build --delete-conflicting-outputs`:通過。
- `flutter analyze`:無新增 error(existing 622 條 pre-existing lint
  warning/info 不變)。
- `flutter test`:全量 1151 條測試通過,含新增的
  `test/repositories/project_category_budget_test.dart`、
  `test/sync/project_partial_update_apply_test.dart`、
  `test/sync/project_category_budget_apply_test.dart`,以及既有
  `test/sync/project_apply_test.dart` 5 條無回歸。
- 手動驗證:待下一步在模擬器/實機上實際操作(建專案→分配子預算→切換期
  間→確認三組分類分組→調低提醒門檻記一筆超標交易確認本機推播),因為這
  次先完成程式碼實作,手動 QA 由使用者驗收前再一起做。
