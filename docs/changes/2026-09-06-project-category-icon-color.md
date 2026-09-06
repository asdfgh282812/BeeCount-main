# 專案分類圖示改用分類專屬顏色

## 問題

專案詳情頁（分類子預算列表、未分配預算列表）與專案分類預算設定頁中，分類圖示一律使用固定灰色底色（`BeeTokens.surfaceCategoryIcon`），與新增交易時的分類選擇器（`CategorySelector`）不一致——後者會依 `Categories.color`（v55 起，見 [category_color_cloud_deferred](../../lib/data/db.dart) 的 `kCategoryColorPalette`）把圖示底色畫成分類專屬色。

## 修改

- [lib/utils/category_utils.dart](../../lib/utils/category_utils.dart)：新增 `CategoryUtils.parseColor(String? hex)`，把 `category_selector.dart` 原本私有的十六進位顏色解析邏輯（`_parseCategoryColor`）搬到共用工具類別，供多處呼叫。
- [lib/widgets/category/category_selector.dart](../../lib/widgets/category/category_selector.dart)：`_CategoryItem` 改呼叫 `CategoryUtils.parseColor`，移除原本重複的私有函式。
- [lib/pages/project/project_detail_page.dart](../../lib/pages/project/project_detail_page.dart)：`_CategoryBudgetTile`（分類子預算列表）與 `_UnsetCategorySectionState._buildRow`（未分配預算列表）的圖示底色改為 `CategoryUtils.parseColor(category.color) ?? 原本灰色 token`，有顏色時圖示改白色以維持對比。
- [lib/pages/project/project_category_budget_edit_page.dart](../../lib/pages/project/project_category_budget_edit_page.dart)：`_buildCategoryCard` 同樣套用分類色。

## 範圍與取捨

- 專案分類預算目前只使用一級分類（`_level1Categories = categories.where((c) => c.level == 1)`），而 `Categories.color` 也只有一級分類會存值，因此這裡不需要處理二級分類繼承父色的情況（`category_selector.dart` 有處理，因為那邊會顯示二級分類）。
- 舊資料或沒有配到顏色的分類（`category.color == null`）維持原本灰色 token 底色，不影響既有外觀。
- 未動到 `lib/pages/budget/widgets/category_budget_tile.dart`（一般預算頁用的 `CategoryBudgetTile`，非專案頁）——它也有同樣「不讀分類色」的狀況，但使用者這次需求限定在「專案」頁面，此檔案留待之後有需要再處理。
