# 分类编辑页：图标改为点击弹窗选择 + 颜色选中态可见性修正

## 背景

用户反馈两点（对比 `ProjectEditPage` 的交互）：

1. 新建/编辑分类时，系统图标是直接把整套 `GroupedIconGrid`（十几个分组、上百个图标）铺在页面里，而专案（Project）的图标选择是点击一个小预览块后弹出底部选择器。分类页应该跟专案保持一致的交互。
2. 编辑一个已经设过颜色的一级分类时，颜色选择器的调色盘里看不出哪个色块是当前选中的。

## 改动

### `lib/pages/category/category_edit_page.dart`

- 图标区块：把原本直接内嵌的 `GroupedIconGrid` 换成 `_buildSystemIconSection`——一个跟旁边"自定义图标"选项同款样式的可点击卡片（预览当前图标 + "点击选择/更换图标" 提示 + 选中态勾选图标），点击后由 `_pickSystemIcon` 弹出 `showModalBottomSheet` + `DraggableScrollableSheet`，里面才放完整的 `GroupedIconGrid`。弹窗结构直接照抄 `ProjectEditPage._pickIcon` 的样式（标题栏 + 关闭按钮 + 可滚动网格），保持两个编辑页体验一致。
- 颜色区块：`_buildColorPicker` 里选中态的描边/勾选颜色，从"跟随 App 深浅色主题"（`BeeTokens.isDark(context)`）改成"跟随色块自身明暗"（复用已有的 `_isLightColor` 逻辑）。原来的逻辑在深色主题下固定用白色描边，遇到调色盘里柠檬黄（`#CDDC39`）、亮绿（`#00E676`）这类本身就偏浅的颜色时，白色描边跟色块几乎融为一体，选中状态形同虚设。现在描边色和勾选图标色统一从色块本身的亮度算，保证任何 App 主题、任何色块都有足够对比度。另外选中色块加了个从 40px 到 44px 的 `AnimatedContainer` 放大效果，让选中项在 20 个色块的调色盘里更显眼。

### `lib/l10n/app_en.arb` / `lib/l10n/app_zh_TW.arb`

新增 3 个 key（只更新这两个文件，`app_zh.arb`/`app_ko.arb` 按既定策略不再维护）：
`categorySystemIconTitle`、`categorySystemIconTapToSelect`、`categorySystemIconTapToChange`，给新的系统图标预览卡片用。

## 取舍 / 未处理

- 没有改动 `GroupedIconGrid` 本身的分组/图标数据，只是改了它的呈现位置（从内嵌改成弹窗里）。
- 没有触碰 `_getCategoryIcon`（分类页私有的图标名→`IconData` 映射，跟 `CategoryService.getCategoryIcon` 有重复）——这是既有的技术债，超出本次 UX 修复的范围，不在这次一并重构。
