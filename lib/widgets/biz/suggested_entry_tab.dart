import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/suggestion_providers.dart';
import 'suggested_category_grid.dart';

/// 「建議」分頁內容——只有一個依演算法排序的類別格,不含金額/帳戶等其他
/// 欄位。點類別後轉交給支出表單(見 `transaction_editor_page.dart` 呼叫
/// [onCategoryPicked] 之後的 `selectCategoryFromSuggestion` + `animateTo`),
/// 完全不複製一份記帳邏輯。
///
/// 這裡刻意不實作 `AutomaticKeepAliveClientMixin`(跟其他 3 個分頁不同)——
/// 讓 `TabBarView` 在切走再切回來時整個重建,`categorySuggestionsProvider`
/// (`autoDispose`)因此自然重新計算,時段/星期訊號不會因為長時間停留在
/// 記帳頁而過期,不需要額外手動 invalidate。
class SuggestedEntryTab extends ConsumerWidget {
  const SuggestedEntryTab({super.key, required this.onCategoryPicked});

  final ValueChanged<Category> onCategoryPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final asyncCategories = ref.watch(categorySuggestionsProvider);
    return asyncCategories.when(
      data: (categories) {
        if (categories.isEmpty) {
          return Center(child: Text(l10n.suggestedTabEmpty));
        }
        return SuggestedCategoryGrid(
          categories: categories,
          onCategorySelected: onCategoryPicked,
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(child: Text(l10n.commonError)),
    );
  }
}
