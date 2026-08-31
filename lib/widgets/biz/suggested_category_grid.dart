import 'package:flutter/material.dart';

import '../../data/db.dart';
import '../../styles/tokens.dart';
import '../../utils/category_utils.dart';
import '../category_icon.dart';

/// 「建議」分頁的類別格——扁平清單(不分主/子類別手風琴),依
/// [CategorySuggestionService] 算好的分數由高到低排列。視覺沿用既有
/// `CategorySelector` 的圖示圓圈樣式(`BeeTokens.surfaceCategoryIcon`),
/// 保持跟其他分類格一致,不另外發明一套配色。
class SuggestedCategoryGrid extends StatelessWidget {
  const SuggestedCategoryGrid({
    super.key,
    required this.categories,
    required this.onCategorySelected,
  });

  final List<Category> categories;
  final ValueChanged<Category> onCategorySelected;

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
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
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
                  color: BeeTokens.surfaceCategoryIcon(context),
                  shape: BoxShape.circle,
                ),
                child: CategoryIconWidget(
                  category: category,
                  size: 22,
                  color: BeeTokens.iconCategory(context),
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
