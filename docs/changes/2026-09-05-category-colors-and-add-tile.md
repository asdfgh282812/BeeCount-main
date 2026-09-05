# 分类专属颜色 + 记账页分类格「新增」取代「分类管理」按钮

## 背景

用户反馈两点(对照记账页支出/收入分类格截图 vs. moze 的分类选择画面):
1. 分类格网格下方独立的「分类管理」文字按钮不需要,应该把「新增」直接做成
   网格最后一格(跟 moze 一致)。
2. 分类目前全部用同一套灰色圆圈渲染,彼此不好辨认,希望每个分类有自己的
   颜色。

设计决策(经与用户确认):
- 颜色**自动配色**,不做手动颜色选择器 UI。
- 颜色**需要同步**到云端(BeeCount Cloud / Supabase / WebDAV 等)。
- 「新增」格子的改动范围除了记账页支出/收入分类格外,连「建议」分页的
  分类格也一起套用;「建议」分页可能出现二级分类,颜色继承自己的一级
  分类(用户特别强调的点)。

## 数据层:`Categories.color`

- [lib/data/db.dart](../../lib/data/db.dart):`Categories` 表新增
  `color`(nullable TEXT,十六进制字符串如 `#FF9800`)。**只有一级分类存
  值,二级分类不单独存一份**——渲染时向上查父分类的颜色,这样改一级分类
  颜色不需要连带改一堆二级分类行。
  - `schemaVersion` 54 → 55,新增 v55 迁移:`ALTER TABLE` 加列(走既有的
    `_addColumnIfMissing` 幂等 helper)+ 回填既有一级分类颜色——按
    `kind` 分组、依 `sort_order`/`id` 顺序,从新增的
    `kCategoryColorPalette`(20 色,字面量抄自 `TagSeedService` 的预设
    标签色盘,视觉上已验证过一轮好看的色相分布)循环指派。
  - 为什么字面量重抄一份而不是共享同一个 `List`:`TagSeedService` 在
    `services/` 层,反过来被 `data/db.dart` import 会造成数据层依赖服务层
    的分层倒挂,权衡后选择接受这点颜色字面量重复。
  - 迁移测试:[test/data/migration_v55_test.dart](../../test/data/migration_v55_test.dart),
    覆盖「按 kind 独立循环取色」「二级分类不参与回填」两个场景。

- [lib/data/repositories/local/local_category_repository.dart](../../lib/data/repositories/local/local_category_repository.dart):
  - `createCategory` 新建一级分类(`parentId == null`)时,调用新增的
    `_nextAutoColor(kind)` 按「该 kind 下已有多少个一级分类」取模索引色
    盘,跟迁移回填用同一份 `kCategoryColorPalette`,保证「同一顺序位置」
    在两条路径下拿到同一个颜色。创建二级分类(`createSubCategory`)不涉及
    颜色,维持 null。
  - 顺手把两处手动构造 `Category(...)` 的 sharedledger 相关路径
    (`_watchSharedCategoryBySyntheticId`、`getAllCategoriesIncludingShared`)
    和 `watchCategoryWithSubs` 的 raw SQL 映射也带上 `color` 字段——
    否则共享账本 Editor 视角/这条 stream 会永远拿不到颜色(`Category` 是
    Drift 生成类,`color` 是 nullable 字段,不改这几处也能编译,只是数据
    会悄悄丢失)。
  - **刻意没碰**的:`watchCategoriesWithCount`(分类管理页列表用的
    raw SQL,显式列名 SELECT,没带 `color`)——分类管理页列表本身不在这次
    改动范围内(用户的截图是记账页分类格,不是管理页),该页面维持原本的
    灰色渲染。

## 同步:App ↔ BeeCount Cloud

按 `docs/CLOUD_SYNC_INTEGRATION.md` §4 的「新增/修改字段」checklist:
- [lib/cloud/sync/entity_serializer.dart](../../lib/cloud/sync/entity_serializer.dart)
  的 `serializeCategory`:新增 `if (category.color != null) 'color': category.color`,
  跟 `customIconPath`/`communityIconId` 同款可选字段写法。
- [lib/cloud/sync/sync_engine_apply.dart](../../lib/cloud/sync/sync_engine_apply.dart)
  的 `_applyCategoryChange`:update 和 insert 两个分支都加上
  `color: d.Value(payload['color'] as String?)`,跟其它字段一样不做
  `containsKey` 防御(该文件里 `communityIconId` 等既有字段也是这个写法,
  保持一致)。
- `SharedLedgerCategories.color`(镜像表)在 `sync_engine_realtime.dart`
  里其实早就有 `color: d.Value(payload['color'] as String?)` 的写入代码,
  只是过去 `serializeCategory` 从不产出 `color` key 所以一直是死代码——
  这次改动顺带让它真正生效。

**已知限制、刻意不在本次范围内处理**:BeeCount Cloud(独立仓库
`../BeeCount-Cloud/`)服务端的 category 投影(`projection.upsert_category`)
是否已经认得 `color` 这个 key、会不会把它落到自己的表并在下次 pull 时原样
回传,取决于该仓库自己的 schema/代码,这次完全没有触碰那个仓库。在
Cloud 端更新之前:
- 同一台设备上颜色能立刻生效(本地已经写好了);
- 但 push 上去的 `color` 大概率会被 Cloud 端忽略/丢弃(它的表没有这个
  列),其它设备 pull 下来大概率看不到颜色,直到 Cloud 端也做一次对应的
  schema + 投影更新。
这跟以往「App 先做、Cloud 端另起一次改动」的既有模式一致(可参考仓库里
类似的分阶段处理先例)。

## UI:记账页分类格

- [lib/widgets/category/category_selector.dart](../../lib/widgets/category/category_selector.dart)
  的 `_buildCompactGrid`(单页式记账表单的支出/收入分类格,即用户截图
  那个画面):
  - 移除网格下方独立的「分类管理」按钮(齿轮图标 + 文字)。
  - 网格最后一格固定改成新增的 `_CategoryAddItem`(「+ 新增」),点击直接
    `Navigator.push(CategoryEditPage(kind: widget.kind))`——跟
    `CategoryManagePage._addCategory` 用的是同一个入口页面,不是另外再做
    一套新增流程。
  - 展开二级分类的子网格维持原本「返回」在第一格,不额外加新增格(跟
    moze 参考图一致,新增格只在主类别层级出现)。
  - **确认不会让用户找不到分类管理**:`data_management_page.dart` 里还有
    一条独立入口能进 `CategoryManagePage`;`_buildAccordionList`(全页面
    场景,如分类管理页自己内嵌调用 `CategorySelector` 手风琴模式)的
    「分类管理」按钮完全没动。
  - `_CategoryItem` 颜色渲染:一级分类用自己的 `category.color`,二级分类
    用 `parent?.color`(`parent` 字段过去一直存在但没人传,这次两处调用点
    补上实参)。颜色存在时背景实心色 + 白色图标(视觉上更接近 moze 参考
    图的「醒目实心圆」,而不是原本 25% 透明度的浅色 tint);选中态额外加
    一圈 `primaryColor` 描边表示选中,取代原本靠 tint 深浅区分选中的做法。
    分类没有颜色(旧数据边界情况、转账分类等)时完全退回原本的灰色 token
    渲染,零视觉变化。

- [lib/widgets/biz/suggested_category_grid.dart](../../lib/widgets/biz/suggested_category_grid.dart) +
  [lib/widgets/biz/suggested_entry_tab.dart](../../lib/widgets/biz/suggested_entry_tab.dart)
  (记账页「建议」分页):同样加最后一格「新增」,`kind` 固定传
  `'expense'`——建议清单本身混合收入/支出,没有单一 kind 可用,取最常见
  的支出场景当默认,使用者仍可在新增页里自行切换成收入。颜色解析:
  `SuggestedEntryTab` 额外 watch 既有的 `categoriesProvider`(App 内多处
  已在用,通常已有缓存)整理出 `id → color` 的 map 传给
  `SuggestedCategoryGrid`,让「建议」清单里可能出现的二级分类也能反查到
  父分类颜色。

## 测试

- 新增 [test/data/migration_v55_test.dart](../../test/data/migration_v55_test.dart)。
- 跑过 `flutter analyze`(无新增 error/warning)、
  `flutter test test/data/ test/repositories/ test/widgets/`(全部通过)。
- **未做的验证**:这台机器上 iOS 模拟器未配置(`xcode-select` 指向的不是
  Xcode,需要用户自己跑一次
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)、没有
  Android 模拟器、且这个 App 本身不支持 web 平台构建(`sqlite3`/`record`
  等插件依赖 `dart:ffi`,web target 编译直接报错)——这次没能在真机/模拟器
  上肉眼确认颜色渲染与新增格交互,只验证了数据层迁移测试 + 现有测试套件
  未回归 + 静态分析干净。建议合并前用
  `flutter run --flavor dev` 实机走一遍记账页支出/收入分类格 + 建议分页,
  确认颜色好看、选中态描边看得清楚、点最后一格能正常跳到新增分类页。
