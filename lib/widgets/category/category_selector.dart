import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../providers.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/shared_ledger_providers.dart';
import '../../utils/category_utils.dart';
import '../../utils/shared_ledger_picker_filter.dart';
import '../../styles/tokens.dart';
import '../category_icon.dart';
import '../../pages/category/category_manage_page.dart';

/// 分类选择器组件
/// 用于选择收入或支出分类，支持二级分类原地展开
class CategorySelector extends ConsumerStatefulWidget {
  /// 分类类型：'expense' 或 'income'
  final String kind;

  /// 分类选择回调
  final ValueChanged<Category> onCategorySelected;

  /// 初始选中的分类ID（可选）
  final int? initialCategoryId;

  /// 為 true 時:主類別網格固定 2 行(超出內部滾動,5 欄/行,圖示更小),點擊
  /// 有子類別的項目直接切換整個網格區域到子類別列表(index 0 固定「返回」),
  /// 不再原地手風琴展開。目前只有單頁式記帳表單
  /// (`transaction_entry_form.dart`)用這個模式;分類管理/預算/搜尋等全頁面
  /// 場景維持原本「不限高度 + 原地展開二級分類」的行為,呼叫方不用改。
  final bool compactGrid;

  const CategorySelector({
    super.key,
    required this.kind,
    required this.onCategorySelected,
    this.initialCategoryId,
    this.compactGrid = false,
  });

  @override
  ConsumerState<CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends ConsumerState<CategorySelector> {
  int? _expandedCategoryId; // 当前展开的一级分类ID
  int? _selectedId; // 记录当前点击的分类用于高亮
  bool _scrolled = false; // 标记是否已滚动
  final Map<int, GlobalKey> _keys = {}; // 分类ID到GlobalKey的映射

  @override
  void initState() {
    super.initState();
    // 如果有初始分类ID，需要在数据加载后设置选中状态和展开状态
    if (widget.initialCategoryId != null) {
      _selectedId = widget.initialCategoryId;
      _initializeExpandedState();
    }
  }

  Future<void> _initializeExpandedState() async {
    if (widget.initialCategoryId == null) return;

    final repo = ref.read(repositoryProvider);
    final initialId = widget.initialCategoryId!;

    // §7 共享账本:initialCategoryId 是 synthetic 负数时,主表 getCategoryById
    // 查不到 → 走 SharedLedgerCategories 反查,通过 parent_sync_id 派生 parent
    // 的 synthetic id,正确展开父分类。
    if (initialId < 0 && repo is LocalRepository) {
      final ctxLedgerId = ref.read(currentLedgerIdProvider);
      final ctx = await repo.db.loadLedgerPickerContext(ctxLedgerId);
      final ledgerSyncId = ctx?.ledgerSyncId;
      if (ledgerSyncId != null) {
        final rows = await (repo.db.select(repo.db.sharedLedgerCategories)
              ..where((t) => t.ledgerSyncId.equals(ledgerSyncId)))
            .get();
        for (final s in rows) {
          if (syntheticIdForSyncId(s.syncId) == initialId) {
            if ((s.level) == 2 &&
                s.parentSyncId != null &&
                s.parentSyncId!.isNotEmpty) {
              setState(() {
                _expandedCategoryId = syntheticIdForSyncId(s.parentSyncId!);
              });
            }
            return;
          }
        }
      }
      return;
    }

    final initialCategory = await repo.getCategoryById(initialId);
    if (initialCategory != null &&
        initialCategory.level == 2 &&
        initialCategory.parentId != null) {
      // 如果是二级分类，展开其父分类
      setState(() {
        _expandedCategoryId = initialCategory.parentId;
      });
    }
  }

  /// §7 共享账本 picker 过滤 — Editor + 共享账本 只显示 Owner 的 SharedLedger
  /// 行,按 kind 过滤;单人账本 / Owner 视角走主表 getTopLevelCategories。
  Future<List<Category>> _loadFilteredTopLevel() async {
    final repo = ref.read(repositoryProvider);
    final cats = await repo.getTopLevelCategories(widget.kind);
    if (repo is! LocalRepository) return cats;
    final currentLedgerId = ref.read(currentLedgerIdProvider);
    final ctx = await repo.db.loadLedgerPickerContext(currentLedgerId);
    return repo.db.filterCategoriesForLedger(cats, ctx, kind: widget.kind);
  }

  @override
  Widget build(BuildContext context) {
    // §7 共享账本:WS shared_resource_change 推送后 tick bump,触发 rebuild
    // → FutureBuilder 拿到新 Future → 重查 SharedLedgerCategories。否则 A
    // 在 web/mobile 改分类名,B 这边 picker 永远显示旧名,要重启 app。
    ref.watch(sharedResourceRefreshProvider);
    return FutureBuilder<List<Category>>(
      future: _loadFilteredTopLevel(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final topLevelCategories = snapshot.data!;

        if (topLevelCategories.isEmpty) {
          return Center(
            child: Text(AppLocalizations.of(context).categoryEmpty),
          );
        }

        return FutureBuilder<Map<int, List<Category>>>(
          future: _loadSubCategories(topLevelCategories),
          builder: (context, subSnapshot) {
            if (!subSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final subCategoriesMap = subSnapshot.data!;
            if (widget.compactGrid) {
              return _buildCompactGrid(
                  context, topLevelCategories, subCategoriesMap);
            }
            return _buildAccordionList(
                context, topLevelCategories, subCategoriesMap);
          },
        );
      },
    );
  }

  /// 緊湊模式:主類別/子類別網格固定 2 行,點擊有子類別的項目切換整個網格
  /// (不原地展開),index 0 固定「返回」——見 [CategorySelector.compactGrid]。
  Widget _buildCompactGrid(
    BuildContext context,
    List<Category> topLevelCategories,
    Map<int, List<Category>> subCategoriesMap,
  ) {
    final expandedId = _expandedCategoryId;
    final items = expandedId == null
        ? topLevelCategories
        : (subCategoriesMap[expandedId] ?? const <Category>[]);
    final showBack = expandedId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          // 固定 2 行高度,超出的项目在 GridView 自身内部滚动浏览,不再靠外层
          // ListView 撑开、把画面挤成 3 行以上。
          height: 68 * 2 + 6,
          child: GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 4,
              mainAxisSpacing: 6,
              mainAxisExtent: 68,
            ),
            itemCount: items.length + (showBack ? 1 : 0),
            itemBuilder: (context, index) {
              if (showBack && index == 0) {
                return _CategoryBackItem(
                  onTap: () => setState(() => _expandedCategoryId = null),
                );
              }
              final cat = items[showBack ? index - 1 : index];
              final children = subCategoriesMap[cat.id] ?? const <Category>[];
              final hasChildren = !showBack && children.isNotEmpty;
              return _CategoryItem(
                category: cat,
                selected: _selectedId == cat.id,
                hasChildren: hasChildren,
                isSubCategory: showBack,
                compact: true,
                onTap: () {
                  if (hasChildren) {
                    setState(() => _expandedCategoryId = cat.id);
                    return;
                  }
                  setState(() => _selectedId = cat.id);
                  widget.onCategorySelected(cat);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: InkWell(
            onTap: () {
              final tabIndex = widget.kind == 'expense' ? 0 : 1;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CategoryManagePage(initialTabIndex: tabIndex),
                ),
              );
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.settings_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).mineCategoryManagement,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 舊版手風琴模式(全頁面場景維持原行為):主類別 4 欄不限行數,點有子類
  /// 別的項目在同一個 ListView 裡原地插入二級分類卡片。
  Widget _buildAccordionList(
    BuildContext context,
    List<Category> topLevelCategories,
    Map<int, List<Category>> subCategoriesMap,
  ) {
    // 滚动到初始选中的分类
    if (!_scrolled && widget.initialCategoryId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // 获取初始分类信息以确定滚动目标
        final repo = ref.read(repositoryProvider);
        final initialCategory =
            await repo.getCategoryById(widget.initialCategoryId!);

        if (initialCategory != null) {
          int scrollTargetId;

          // 如果是二级分类，滚动到父分类；否则滚动到自己
          if (initialCategory.level == 2 && initialCategory.parentId != null) {
            scrollTargetId = initialCategory.parentId!;
          } else {
            scrollTargetId = initialCategory.id;
          }

          final key = _keys[scrollTargetId];
          final ctx = key?.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.0,
              duration: const Duration(milliseconds: 250),
            );
            _scrolled = true;
          }
        }
      });
    }

    // 构建显示项列表：网格行 + 可能的二级分类容器
    final displayItems = <Widget>[];

    // 按每4个一组显示一级分类
    for (int i = 0; i < topLevelCategories.length; i += 4) {
      final endIndex = (i + 4).clamp(0, topLevelCategories.length);
      final rowItems = topLevelCategories.sublist(i, endIndex);

      // 为该行第一个分类创建key（用于滚动定位）
      final firstCategoryInRow = rowItems.first;

      // 添加网格行
      displayItems.add(
        Container(
          key: _keys.putIfAbsent(firstCategoryInRow.id, () => GlobalKey()),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.9,
            ),
            itemCount: rowItems.length,
            itemBuilder: (context, index) {
              final topCat = rowItems[index];
              final children = subCategoriesMap[topCat.id] ?? [];
              final hasChildren = children.isNotEmpty;

              return _CategoryItem(
                category: topCat,
                selected: _selectedId == topCat.id,
                hasChildren: hasChildren,
                expanded: _expandedCategoryId == topCat.id,
                onTap: () {
                  if (hasChildren) {
                    // 有子分类，切换展开/折叠
                    setState(() {
                      if (_expandedCategoryId == topCat.id) {
                        _expandedCategoryId = null;
                      } else {
                        _expandedCategoryId = topCat.id;
                      }
                    });
                  } else {
                    // 无子分类，直接选中，同时关闭展开的二级分类
                    setState(() {
                      _selectedId = topCat.id;
                      _expandedCategoryId = null; // 关闭展开的二级分类
                    });
                    widget.onCategorySelected(topCat);
                  }
                },
              );
            },
          ),
        ),
      );

      // 检查这一行中是否有展开的分类，如果有则添加二级分类容器
      for (int j = 0; j < rowItems.length; j++) {
        final topCat = rowItems[j];
        final children = subCategoriesMap[topCat.id] ?? [];
        final hasChildren = children.isNotEmpty;

        if (_expandedCategoryId == topCat.id && hasChildren) {
          displayItems.add(
            const SizedBox(height: 12),
          );
          displayItems.add(
            _SubcategorySelectorCard(
              parentCategory: topCat,
              subCategories: children,
              selectedId: _selectedId,
              onSubCategoryTap: (cat) {
                setState(() => _selectedId = cat.id);
                widget.onCategorySelected(cat);
              },
            ),
          );
          break; // 每行只展开一个
        }
      }

      if (i + 4 < topLevelCategories.length) {
        displayItems.add(const SizedBox(height: 16));
      }
    }

    // 添加设置按钮
    displayItems.add(const SizedBox(height: 24));
    displayItems.add(
      Center(
        child: InkWell(
          onTap: () {
            // expense: tab 0, income: tab 1
            final tabIndex = widget.kind == 'expense' ? 0 : 1;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CategoryManagePage(
                  initialTabIndex: tabIndex,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).mineCategoryManagement,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    displayItems.add(const SizedBox(height: 12));

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      children: displayItems,
    );
  }

  Future<Map<int, List<Category>>> _loadSubCategories(
      List<Category> topLevelCategories) async {
    final repo = ref.read(repositoryProvider);
    final result = <int, List<Category>>{};

    // §7 共享账本:Editor 视角下父分类 id 是 synthetic 负数,主表
    // getSubCategories(parentInt) 查不到。改走 SharedLedgerCategories 表按
    // parent_sync_id 反查;非共享 / Owner 走原主表路径。
    final currentLedgerId = ref.read(currentLedgerIdProvider);
    LedgerPickerContext? ctx;
    if (repo is LocalRepository) {
      ctx = await repo.db.loadLedgerPickerContext(currentLedgerId);
    }
    final isSharedEditor = ctx?.isEditorInShared == true;

    for (final cat in topLevelCategories) {
      List<Category> children;
      if (isSharedEditor && cat.id < 0 && repo is LocalRepository) {
        children = await repo.db.getSharedSubCategoriesBySyntheticParentId(
            cat.id, ctx!.ledgerSyncId!);
      } else {
        children = await repo.getSubCategories(cat.id);
      }
      if (children.isNotEmpty) {
        result[cat.id] = children;
      }
    }

    return result;
  }
}

/// 二级分类选择器卡片
class _SubcategorySelectorCard extends ConsumerWidget {
  final Category parentCategory;
  final List<Category> subCategories;
  final int? selectedId;
  final ValueChanged<Category> onSubCategoryTap;

  const _SubcategorySelectorCard({
    required this.parentCategory,
    required this.subCategories,
    required this.selectedId,
    required this.onSubCategoryTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isDark = BeeTokens.isDark(context);

    return Container(
      decoration: BoxDecoration(
        color: BeeTokens.surfacePopoverCard(context),
        borderRadius: BorderRadius.circular(12),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.15),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ],
        border: isDark ? Border.all(color: BeeTokens.border(context)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          itemCount: subCategories.length,
          itemBuilder: (context, index) {
            final subCat = subCategories[index];
            return _CategoryItem(
              category: subCat,
              selected: selectedId == subCat.id,
              isSubCategory: true,
              onTap: () => onSubCategoryTap(subCat),
            );
          },
        ),
      ),
    );
  }
}

/// 分类项组件
class _CategoryItem extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;
  final bool selected;
  final bool isSubCategory;
  final Category? parent;
  final bool hasChildren;
  final bool expanded;
  // compactGrid 模式(单页式记账表单)下图示与间距更小,见
  // CategorySelector.compactGrid。
  final bool compact;

  const _CategoryItem({
    required this.category,
    required this.onTap,
    this.selected = false,
    this.isSubCategory = false,
    this.parent,
    this.hasChildren = false,
    this.expanded = false,
    this.compact = false,
  });

  /// 构建图标组件（支持自定义图标）
  Widget _buildIcon(BuildContext context, double size, Color color) {
    // 使用统一的 CategoryIconWidget
    return CategoryIconWidget(
      category: category,
      size: size,
      color: color,
      circular: true, // 使用圆形
    );
  }

  @override
  Widget build(BuildContext context) {
    // 二级分类使用较小的图标和缩进；compact 模式下再进一步缩小,给 5 列/
    // 2 行的网格腾出空间(见 CategorySelector.compactGrid)。
    final iconSize =
        compact ? (isSubCategory ? 36.0 : 40.0) : (isSubCategory ? 48.0 : 56.0);
    final fontSize = compact ? 10.0 : (isSubCategory ? 11.0 : 12.0);
    final iconGlyphSize =
        compact ? (isSubCategory ? 16.0 : 18.0) : (isSubCategory ? 20.0 : 24.0);
    final spacing = compact ? 4.0 : 8.0;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: selected
                      ? primaryColor.withValues(alpha: 0.25)
                      : isSubCategory
                          ? BeeTokens.surfaceCategoryIconLight(context)
                          : BeeTokens.surfaceCategoryIcon(context),
                  shape: BoxShape.circle,
                ),
                child: _buildIcon(
                  context,
                  iconGlyphSize,
                  selected ? primaryColor : BeeTokens.iconCategory(context),
                ),
              ),
              // 有子分类时在图标右下角显示三个点（完全分开，不重叠）
              if (hasChildren && !isSubCategory)
                Positioned(
                  right: compact ? -4 : -6,
                  bottom: compact ? -4 : -6,
                  child: Container(
                    width: compact ? 15 : 20,
                    height: compact ? 15 : 20,
                    decoration: BoxDecoration(
                      color: selected
                          ? primaryColor.withValues(alpha: 0.25)
                          : BeeTokens.surfaceCategoryIcon(context),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: BeeTokens.surface(context),
                        width: compact ? 1.5 : 2,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.more_horiz,
                        size: compact ? 11 : 14,
                        color: selected
                            ? primaryColor
                            : BeeTokens.iconCategory(context),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: spacing),
          Text(
            CategoryUtils.getDisplayName(category.name, context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: fontSize,
                  color: isSubCategory
                      ? BeeTokens.textSecondary(context)
                      : BeeTokens.textPrimary(context),
                ),
          ),
        ],
      ),
    );
  }
}

/// compactGrid 模式下子類別網格的 index 0 固定項目:返回上一層主類別列表。
class _CategoryBackItem extends StatelessWidget {
  final VoidCallback onTap;

  const _CategoryBackItem({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: BeeTokens.surfaceCategoryIconLight(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              size: 18,
              color: BeeTokens.iconCategory(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).commonBack,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: BeeTokens.textSecondary(context),
                ),
          ),
        ],
      ),
    );
  }
}
