import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../pages/category/category_edit_page.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../category_icon.dart';

/// 「建議」分頁的類別格——扁平清單(不分主/子類別手風琴),依
/// [CategorySuggestionService] 算好的分數由高到低排列。最後一格固定
/// 「新增」,跟 [CategorySelector] 的主類別格一致(與 moze 一致);點擊
/// 新增分類的 kind 固定 'expense'——建議清單本身混合收支,没有单一 kind
/// 可用,取最常见的支出场景当默认,使用者仍可在新增页里自行切换。
class SuggestedCategoryGrid extends StatelessWidget {
  const SuggestedCategoryGrid({
    super.key,
    required this.categories,
    required this.onCategorySelected,
    this.colorByCategoryId = const {},
  });

  final List<Category> categories;
  final ValueChanged<Category> onCategorySelected;

  /// 全量分類 id → 顏色 hex 的 map,用來給二級分類的建議格反查父分類顏色
  /// (二級分類自己不存顏色,見 Categories.color 的欄位註解)。
  final Map<int, String?> colorByCategoryId;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 12,
        childAspectRatio: 0.8,
      ),
      itemCount: categories.length + 1,
      itemBuilder: (context, index) {
        if (index == categories.length) {
          return InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CategoryEditPage(kind: 'expense'),
              ),
            ),
            borderRadius: BorderRadius.circular(48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add,
                      size: 22, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLocalizations.of(context).commonAdd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: BeeTokens.textPrimary(context),
                      ),
                ),
              ],
            ),
          );
        }

        final category = categories[index];
        final hex = category.parentId != null
            ? (colorByCategoryId[category.parentId] ?? category.color)
            : category.color;
        final resolvedColor = _parseColor(hex);
        return InkWell(
          onTap: () => onCategorySelected(category),
          borderRadius: BorderRadius.circular(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: resolvedColor ?? BeeTokens.surfaceCategoryIcon(context),
                  shape: BoxShape.circle,
                ),
                child: CategoryIconWidget(
                  category: category,
                  size: 22,
                  color: resolvedColor != null
                      ? Colors.white
                      : BeeTokens.iconCategory(context),
                  circular: true,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                CategoryUtils.getDisplayName(category.name, context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: BeeTokens.textPrimary(context),
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 解析分类颜色十六进制字符串(如 "#FF9800")。跟 category_selector.dart
/// 的 _parseCategoryColor 同款写法(两处都是私有小函数,不额外抽共用 util,
/// 沿用本專案 tag_chip.dart/tag_edit_page.dart 既有的重复惯例)。
Color? _parseColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    var value = hex;
    if (value.startsWith('#')) {
      value = value.substring(1);
    }
    if (value.length == 6) {
      value = 'FF$value';
    }
    return Color(int.parse(value, radix: 16));
  } catch (_) {
    return null;
  }
}
