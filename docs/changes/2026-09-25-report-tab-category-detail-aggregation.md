# 「洞察」更名為「報表」+ 分類匯總頁聚合一級分類的子分類交易

## 背景

底部導覽列「洞察」頁(`lib/pages/main/analytics_page.dart`)點擊圓餅圖(`CategoryPieChart`)上的一級分類扇區(例如「個人」)後，會進入「分類匯總」頁(`CategoryDetailPage`)，但畫面永遠顯示「暫無交易記錄」。

原因：新增交易時，若一級分類已有子分類，UI 強制使用者只能選子分類(見 `category_selector.dart`)，交易的 `categoryId` 實際上記在子分類上，一級分類自己的 id 底下不會有任何交易。而 `CategoryPieChart._openCategoryDetail` 一律只用被點分類自身的 id 去查詢，導致父分類永遠查空。

排行清單(`CategoryRankRow`)其實已經用「展開/收合」繞開了這個問題(點一級分類只展開子分類列，不會導覽到空頁面)，但圓餅圖沒有這個防呆，直接導覽。

## 變更

### 1. 底部導覽列更名(`lib/l10n/app_en.arb` / `app_zh_TW.arb` 的 `tabInsights`)
「洞察」→「報表」(en: "Stats" → "Report")。只改了 `app_en.arb`/`app_zh_TW.arb`，未動 `app_zh.arb`/`app_ko.arb`(見既有 l10n 維護政策)。

### 2. Repository 層新增聚合查詢
- `CategoryRepository.watchTransactionsByCategories(List<int> categoryIds, {int? ledgerId})`(新方法，`category_repository.dart`)
- 實作於 `LocalCategoryRepository`(`local_category_repository.dart`)：id 只有一個時退化呼叫既有的 `watchTransactionsByCategory`；多個 id 時走 `categoryId.isIn(...)`。另外處理了共享帳本(§7)synthetic 負 id 的子分類——這類 id 不記在 `categoryId` 欄位而是 `categorySyncIdOverride`，混在正 id 清單裡時要分開查再用 `|` 合併條件，否則共享帳本情境下同樣的空清單問題會用另一種方式重現。
- `LocalRepository` 補上對應委派方法。

### 3. `CategoryDetailPage`(`lib/pages/transaction/category_detail_page.dart`)
- 新增可選建構參數 `childCategoryIds`：傳入時，頁面把 `categoryId` 自身 + 這些子分類 id 一起丟給 `watchTransactionsByCategories`，彙總後計算的總筆數/總金額/平均金額才會是正確的「父分類 + 全部子分類」口徑。
- 交易列表原本不分青紅皂白，每一列的圖示/分類名稱都寫死用 `widget.categoryId` 對應的(父)分類——單一分類查詢時沒差，但現在同一頁可能混著父分類自身 + 好幾個子分類的交易，繼續寫死會讓每筆交易都顯示成同一個(父)分類的圖示/名稱。改成用 `categoriesProvider` 建 `categoriesById` 表，每筆交易按自己的 `transaction.categoryId` 查對應分類顯示(查不到才 fallback 回原本寫死的那個)。點交易列的「編輯/搬遷」按鈕沒有動——那兩個動作本來就是針對 `widget.categoryId` 這個一級分類本身，`migrateCategoryTransactions` 早就有處理子分類的邏輯，不受影響。

### 4. `CategoryPieChart._openCategoryDetail`(`lib/widgets/charts/category_pie_chart.dart`)
點擊扇區時，把該分類 `item.subCategories` 的 id 列表一併透過新的 `childCategoryIds` 參數傳給 `CategoryDetailPage`。

## 刻意不動的部分

- `CategoryRankRow`(排行清單)點一級分類仍是展開/收合，沒有改成也導覽到聚合詳情頁——原本的展開行為已經是可用的 UX，不在這次修的問題範圍內。
- 「分類匯總」頁的「搬遷分類」按鈕沒有處理成「聚合搬遷」，因為它本來就是對 `widget.categoryId`(父分類自身)操作，而 `migrateCategoryTransactions` 已經會連同子分類一起搬，維持原樣即可。

## 測試

新增 `test/data/repositories/local/watch_transactions_by_categories_test.dart`，涵蓋：父分類自身查詢為空但聚合子分類後能查到、跨帳本過濾仍生效、單一 id 時退化為原查詢。`flutter analyze` 無新增錯誤；`flutter test` 全量跑過(唯一失敗的 `calendar_month_jump_test.dart` 為既有、與本次變更無關的失敗，已用 `git stash` 驗證改動前同樣會炸)。

## 入口

功能本身沒有新增入口，是修正既有入口(底部導覽「報表」→ 圓餅圖點一級分類)的既有 bug。
