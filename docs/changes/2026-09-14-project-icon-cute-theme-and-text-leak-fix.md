# 修正專案圖標的兩個顯示問題

## 問題 1：可愛圖標套用到專案後仍顯示一般圖標

`CategoryIconWidget`（`lib/widgets/category_icon.dart`）在渲染「分類」圖標時，會
`watch(categoryIconStyleProvider)`，可愛主題下改呼叫 `CuteCategoryIcon.maybeBuild`
畫手繪線稿。但「專案」（`Project`）沒有完整的 `Category` 物件（沒有
`iconType`/`customIconPath`/`color` 等欄位），所有專案圖標渲染點都是直接呼叫不
感知主題的 `CategoryService.iconOrEmojiWidget(icon: ..., color: ..., size: ...)`
——不管當下是不是可愛主題，一律畫 Material 圖示。使用者在專案圖標選擇器裡選
的可愛款其實跟一般款共用同一個 icon key 字串（差別本來就该只在渲染），但渲染
端完全沒有走可愛分支，導致「選了可愛圖標，套用後看到的還是一般圖標」。

## 問題 2：明細頁看到圖標名稱文字，而非圖標圖案

`lib/widgets/biz/transaction_list_item.dart` 的 `_buildProjectChip`（交易列表項
目裡的專案 pill）把 `project.icon`（原始 icon key 字串，例如 `shopping_cart`）
直接字串拼接進 `Text('${p.icon} ${p.name}')`，完全沒有經過圖標解析，使用者看到
的自然是一串英文 key 而不是圖案。

## 修法

新增 `ThemedIconGlyph`（`lib/widgets/category_icon.dart`），一個自帶
`ConsumerWidget` 的「icon key 字符串 → 圖標 widget」渲染元件：
- emoji 字串直接畫 `Text`（沿用 `CategoryService.looksLikeEmoji` 的判斷）；
- 可愛主題下呼叫 `CuteCategoryIcon.maybeBuild` 畫手繪線稿；
- 否則落回 `Icon(CategoryService.getCategoryIcon(icon))`。

這個元件專門給「只存一個 icon key 字串、沒有完整 `Category` 物件」的場景使用
（目前是 `Project`）；有完整 `Category` 物件的地方仍應該用既有的
`CategoryIconWidget`（支援自訂圖片、分類色底線等）。

把所有專案圖標渲染點從 `CategoryService.iconOrEmojiWidget` 改成
`ThemedIconGlyph`：
- `lib/pages/project/project_edit_page.dart`（編輯頁圖標預覽）
- `lib/pages/project/project_overview_page.dart`（專案列表卡片）
- `lib/pages/project/project_detail_page.dart`（專案詳情頁頭部）
- `lib/widgets/biz/project_picker.dart`（記帳時的專案選擇下拉列表）
- `lib/widgets/biz/transaction_detail_card.dart`（交易詳情卡片的專案列，原本
  已經是圖標 widget，只是不感知可愛主題）

`lib/widgets/biz/transaction_list_item.dart` 的 `_buildProjectChip` 額外拆成
`Row(ThemedIconGlyph + Text(p.name))`，不再把 icon key 字串併進 `Text`。

## 刻意不動的部分

`CategoryService.iconOrEmojiWidget` 本身沒刪，仍保留給不需要感知可愛主題、或
確定只會拿到完整 emoji（如 Web 端專案圖示的自由輸入）的呼叫端使用；只是把
App 內所有「渲染 `Project.icon`」的呼叫點都換掉了。
