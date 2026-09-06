# 子分類顏色繼承缺口修正 (2026-09-07)

## 背景

`Categories.color`（v55 引入）只會存在一級分類上，二級分類設計上要在渲染時繼承父分類顏色（見 `lib/data/db.dart:137-139` 註解、`docs/changes/2026-08-15-category-icon-color-picker-ux.md`）。該次改動已修好 `category_selector.dart`（新增交易的分類選擇器）與 `category_manage_page.dart` 的 `_CategoryCard`（分類管理頁一級分類方塊），但留了一句待辦：`_CategoryItem.parent` 從未在任何建構點被傳入，二級分類分支永遠是 dead code。

使用者回報的實際現象：專案頁「未分配預算」清單裡的二級分類（例如「晚餐」，掛在「飲食」底下）顯示灰色圖示，而同一顆分類在新增交易的分類選擇器中卻正確顯示為藍色（父分類「飲食」的顏色）——同一分類在不同畫面顏色不一致。

## 修改內容

### 1. `lib/pages/category/category_manage_page.dart` — 分類管理頁「子分類」彈窗

此彈窗（點進一級分類後跳出的 `_SubcategoryDialog`）就是待辦註解說的那個「dead code」分支所在畫面，之前完全沒有把父分類顏色傳下去，圖示背景/文字色一律用 `Theme.of(context).colorScheme.primary`：

- 對話框標題列（`:972` 附近）：改用 `CategoryUtils.parseColor(widget.parentCategory.color)`，有值時圖示底色用該顏色、圖示改白色，無值時維持原本 primary 色外觀。
- `_DialogSubCategoryCard`（子分類方塊，`:1122` 附近）：新增 `parentColorHex` 參數，從 `_SubcategoryDialog` 建構處傳入 `widget.parentCategory.color`，同樣套用 `CategoryUtils.parseColor(...) ?? primaryColor` 的既有 pattern。

`_CategoryItem.parent` 那個真正的 dead code（一級分類清單本身不會建出 `isSubCategory: true` 的項目）維持不動——目前唯一會顯示二級分類色塊的畫面就是這個彈窗，已經修好；`_CategoryItem.parent` 若之後真的有地方建構二級分類項目，可以直接沿用 `_CategoryCard` 裡已存在的 `item.isSubCategory ? item.parent?.color : item.category.color` 邏輯（`:813-814`），不需要另外處理。

### 2. `lib/pages/project/project_detail_page.dart` — 專案「已分配/未分配預算」清單

`_CategoryBudgetTile`（`:569`）過去只用 `CategoryUtils.parseColor(category.color)`，對二級分類永遠拿不到顏色（因為二級分類的 `color` 欄位本來就是 null），因而顯示灰色圖示——這正是使用者截圖裡「晚餐」變灰色的原因。

- `_CategoryBudgetTile` 新增 `parent` 欄位，兩個建構點（`allocated`/`unallocated` 清單，`:368`、`:390` 附近）都改成從既有的 `categoryById` map 查出 `entry.key.parentId` 對應的父分類傳入。
- `build()` 內 `resolvedColor` 改成 `category.parentId != null ? parent?.color : category.color`，與 `category_selector.dart:568-569`、`category_manage_page.dart:813-814` 同一套 pattern。

`_UnsetCategorySectionState._buildRow`（`:731`）沒有動：這個清單的來源 `unset`（`:182`）已經先過濾成只剩 `level1Categories`，`category.parentId` 保證是 null，`category.color` 本來就是自己的顏色，沒有這個 bug。

## 不在此次範圍

- `lib/widgets/analytics/category_rank_row.dart`：分析頁的排行列表用的是呼叫端傳入的單一 `color`（用於長條圖排行視覺區分，不是分類自身顏色），一級/二級本來就吃同一個顏色參數，行為已一致，不是本次要修的 bug。
- `lib/widgets/category/subcategory_container.dart`（`SubcategoryContainer`）：全專案 grep 不到任何建構點，是未使用的殘留元件，這次沒有動它。
