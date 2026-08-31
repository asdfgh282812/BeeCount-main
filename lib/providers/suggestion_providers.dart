import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import '../services/data/category_suggestion_service.dart';
import 'budget_providers.dart';
import 'database_providers.dart';

/// 「建議」分頁的排序分類清單。時段/星期是分數輸入之一,`autoDispose` +
/// 呼叫端每次分頁可見時 `ref.refresh`(而非單純 `watch`),避免長時間停留在
/// 記帳頁時這兩個訊號變得過期,見 `SuggestedEntryTab` 的呼叫方式。
final categorySuggestionsProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);
  final budgets = await ref.watch(categoryBudgetsProvider.future);
  return CategorySuggestionService.getSuggestedCategories(
    repository: repo,
    ledgerId: ledgerId,
    budgetUsages: budgets,
    now: DateTime.now(),
  );
});
