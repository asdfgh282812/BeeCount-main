# 分类编辑页：图标改为点击弹窗选择 + 颜色选中态可见性修正 + 分类管理页应用颜色

## 背景

用户反馈三点（对比 `ProjectEditPage` 的交互，以及交易页 `category_selector.dart` 的分类颜色展示）：

1. 新建/编辑分类时，系统图标是直接把整套 `GroupedIconGrid`（十几个分组、上百个图标）铺在页面里，而专案（Project）的图标选择是点击一个小预览块后弹出底部选择器。分类页应该跟专案保持一致的交互。
2. 编辑一个已经设过颜色的一级分类时，颜色选择器的调色盘里看不出哪个色块是当前选中的。
3. `分类管理`页（`CategoryManagePage`）的分类网格里，图标背景一律是主题色的浅色调（或子分类的橙色调），完全没有体现 v55 新增的 `category.color`——同一个分类在记账时的分类选择器（`category_selector.dart`）里明明是彩色的，管理页却看不到。

## 改动

### `lib/pages/category/category_edit_page.dart`

- 图标区块：把原本直接内嵌的 `GroupedIconGrid` 换成 `_buildSystemIconSection`——一个跟旁边"自定义图标"选项同款样式的可点击卡片（预览当前图标 + "点击选择/更换图标" 提示 + 选中态勾选图标），点击后由 `_pickSystemIcon` 弹出 `showModalBottomSheet` + `DraggableScrollableSheet`，里面才放完整的 `GroupedIconGrid`。弹窗结构直接照抄 `ProjectEditPage._pickIcon` 的样式（标题栏 + 关闭按钮 + 可滚动网格），保持两个编辑页体验一致。
- 颜色区块：`_buildColorPicker` 里选中态的描边/勾选颜色，从"跟随 App 深浅色主题"（`BeeTokens.isDark(context)`）改成"跟随色块自身明暗"（复用已有的 `_isLightColor` 逻辑）。原来的逻辑在深色主题下固定用白色描边，遇到调色盘里柠檬黄（`#CDDC39`）、亮绿（`#00E676`）这类本身就偏浅的颜色时，白色描边跟色块几乎融为一体，选中状态形同虚设。现在描边色和勾选图标色统一从色块本身的亮度算，保证任何 App 主题、任何色块都有足够对比度。另外选中色块加了个从 40px 到 44px 的 `AnimatedContainer` 放大效果，让选中项在 20 个色块的调色盘里更显眼。

### `lib/pages/category/category_manage_page.dart`

- `_CategoryCard.build`：新增 `resolvedColor`，逻辑跟 `category_selector.dart` 的 `_CategoryItem` 一致——二级分类没有自己的颜色，继承父分类的（`item.isSubCategory ? item.parent?.color : item.category.color`，经 `CategoryUtils.parseColor` 解析）。图标圆形背景优先用 `resolvedColor`，没配到颜色时才退回原本的"主题色浅色调 / 橙色调"兜底；有颜色时图标本身改用白色，保证在彩色底上可读。
  - 注：`_CategoryItem.parent` 这个字段目前所有构造调用点都没传值（分析器本来就有 `unused_element_parameter` 警告），所以二级分类分支实际上恒为 null——这是既有技术债，不在本次范围内修；本次改动只影响一级分类网格（也是用户截图里展示、需要修的那个）。

### `lib/data/repositories/local/local_category_repository.dart`（真正的根因）

上面 `_CategoryCard` 的改动本身没生效——用户截图验证时，分类管理页的图标背景依旧全是主题色底，编辑页里已经有颜色的分类（如"交通"）打开颜色选择器也完全看不出选中态。往下查发现根因不在任何一处 UI 渲染逻辑，而是 `watchCategoriesWithCount()`（分类管理页和分类编辑页共用的数据源）：这个方法是手写 raw SQL，`SELECT` 清单里根本没有 `c.color`，手动拼 `Category(...)` 对象时自然也没传 `color` 字段——**不管数据库里这一行的 `color` 实际是什么，这条查询路径读出来的 `Category.color` 永远是 `null`**。

- `CategoryManagePage` 的分类网格 watch 的就是这个 provider（`categoriesWithCountProvider` → `watchCategoriesWithCount()`），所以图标背景永远看不到颜色。
- 用户点分类进入编辑页时，`_onEditCategory(item.category)` 传的正是这个残缺的 `Category` 对象，`CategoryEditPage.initState` 里 `_selectedColor = widget.category?.color` 于是初始化成 `null`，颜色选择器自然选不中任何色块——即使数据库里那一行的 `color` 是真实有效的十六进制值。
- 反过来，记账页的分类选择器（`category_selector.dart`）能正确显示颜色，是因为它用的是另一个 provider（`categoriesProvider` → `getAllCategories()`），后者用 Drift 的类型化 `db.select(db.categories)` 会自动选取全部列，没有这个遗漏。

修法：`SELECT` 里加上 `c.color as category_color`（连同 `GROUP BY` 一起补），构造 `Category(...)` 时加上 `color: row.read<String?>('category_color')`。改完之后分类管理页网格、以及从管理页点进去的编辑页，颜色都会跟记账页的分类选择器保持一致。

### `lib/l10n/app_en.arb` / `lib/l10n/app_zh_TW.arb`

新增 3 个 key（只更新这两个文件，`app_zh.arb`/`app_ko.arb` 按既定策略不再维护）：
`categorySystemIconTitle`、`categorySystemIconTapToSelect`、`categorySystemIconTapToChange`，给新的系统图标预览卡片用。

## 取舍 / 未处理

- 没有改动 `GroupedIconGrid` 本身的分组/图标数据，只是改了它的呈现位置（从内嵌改成弹窗里）。
- 没有触碰 `_getCategoryIcon`（分类页私有的图标名→`IconData` 映射，跟 `CategoryService.getCategoryIcon` 有重复）——这是既有的技术债，超出本次 UX 修复的范围，不在这次一并重构。
