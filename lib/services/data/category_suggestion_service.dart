import 'dart:math' as math;

import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../data/repositories/budget_repository.dart';
import '../../models/category_suggestion.dart';

/// 「建議」分頁排序演算法。
///
/// [computeScores] 是純函式(不碰 repository/DB),方便單元測試;
/// [getSuggestedCategories] 負責查資料 + 呼叫 [computeScores] + 反查
/// [Category] 物件,是實際給 UI 用的入口。
///
/// 評分公式(每個訊號正規化到 0~1,budgetPenalty 為乘法懲罰非加項):
/// ```
/// score = budgetPenalty × (0.40·recencyFreq + 0.25·timeOfDay
///                         + 0.10·dayOfWeek + 0.15·accountContext
///                         + 0.10·noteText)
/// ```
class CategorySuggestionService {
  /// 歷史訊號查詢視窗——只看最近 90 天,受益於 `idx_transactions_ledger_type_
  /// happened` 索引,避免全帳本歷史一起掃。
  static const historyWindow = Duration(days: 90);

  /// 「建議」分頁只顯示前 N 個,不用一次全部塞給使用者看(排序意義才會明顯)。
  static const maxSuggestions = 10;

  static const _recencyHalfLifeDays = 14.0;
  static const _weightRecency = 0.40;
  static const _weightTimeOfDay = 0.25;
  static const _weightDayOfWeek = 0.10;
  static const _weightAccountContext = 0.15;
  static const _weightNoteText = 0.10;

  /// 早餐/午餐/下午/晚餐/宵夜 5 個時段桶,索引即桶號。
  static int _timeBucket(DateTime dt) {
    final h = dt.hour;
    if (h >= 5 && h < 10) return 0; // 早餐
    if (h >= 10 && h < 14) return 1; // 午餐
    if (h >= 14 && h < 18) return 2; // 下午
    if (h >= 18 && h < 22) return 3; // 晚餐
    return 4; // 宵夜(22~5)
  }

  static bool _isWeekend(DateTime dt) =>
      dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;

  static double _budgetPenaltyFor(
      int categoryId, List<CategoryBudgetUsage> budgetUsages) {
    for (final b in budgetUsages) {
      if (b.categoryId != categoryId) continue;
      final rate = b.usage.rate;
      if (rate >= 1.0) return 0.3;
      if (rate >= 0.9) return 0.6;
      return 1.0;
    }
    return 1.0;
  }

  static bool _shareToken(String a, String b) {
    final tokensA = a.trim().toLowerCase().split(RegExp(r'\s+'));
    final tokensB = b.trim().toLowerCase().split(RegExp(r'\s+'));
    for (final t in tokensA) {
      if (t.isEmpty) continue;
      if (tokensB.any((u) => u.isNotEmpty && (u.contains(t) || t.contains(u)))) {
        return true;
      }
    }
    return false;
  }

  /// 純函式:給定歷史訊號 + 預算使用率 + 當下時間/情境,算出每個分類的分數,
  /// 由高到低排序。
  static List<CategorySuggestionScore> computeScores({
    required List<CategoryUsageSignal> signals,
    required List<CategoryBudgetUsage> budgetUsages,
    required DateTime now,
    int? contextAccountId,
    String noteText = '',
  }) {
    if (signals.isEmpty) return const [];

    final byCategory = <int, List<CategoryUsageSignal>>{};
    for (final s in signals) {
      byCategory.putIfAbsent(s.categoryId, () => []).add(s);
    }

    final currentBucket = _timeBucket(now);
    final currentWeekend = _isWeekend(now);
    final trimmedNote = noteText.trim();

    // 先算未正規化的 recency 加總,取最大值當分母。
    final rawRecency = <int, double>{};
    for (final entry in byCategory.entries) {
      var sum = 0.0;
      for (final s in entry.value) {
        final ageDays = now.difference(s.happenedAt).inHours / 24.0;
        sum += math.exp(-math.ln2 * ageDays / _recencyHalfLifeDays);
      }
      rawRecency[entry.key] = sum;
    }
    final maxRecency =
        rawRecency.values.fold<double>(0, (a, b) => a > b ? a : b);

    final scores = <CategorySuggestionScore>[];
    for (final entry in byCategory.entries) {
      final categoryId = entry.key;
      final categorySignals = entry.value;
      final total = categorySignals.length;

      final recencyFreq =
          maxRecency > 0 ? (rawRecency[categoryId] ?? 0) / maxRecency : 0.0;

      final timeOfDay =
          categorySignals.where((s) => _timeBucket(s.happenedAt) == currentBucket)
                  .length /
              total;

      final dayOfWeek =
          categorySignals.where((s) => _isWeekend(s.happenedAt) == currentWeekend)
                  .length /
              total;

      final accountContext = contextAccountId == null
          ? 0.0
          : categorySignals.where((s) => s.accountId == contextAccountId).length /
              total;

      final noteTextScore = trimmedNote.isEmpty
          ? 0.0
          : categorySignals
                  .where((s) =>
                      s.note != null &&
                      s.note!.trim().isNotEmpty &&
                      _shareToken(trimmedNote, s.note!))
                  .length /
              total;

      final budgetPenalty = _budgetPenaltyFor(categoryId, budgetUsages);

      final score = budgetPenalty *
          (_weightRecency * recencyFreq +
              _weightTimeOfDay * timeOfDay +
              _weightDayOfWeek * dayOfWeek +
              _weightAccountContext * accountContext +
              _weightNoteText * noteTextScore);

      scores.add(CategorySuggestionScore(
        categoryId: categoryId,
        score: score,
        recencyFreq: recencyFreq,
        timeOfDay: timeOfDay,
        dayOfWeek: dayOfWeek,
        accountContext: accountContext,
        noteText: noteTextScore,
        budgetPenalty: budgetPenalty,
      ));
    }

    scores.sort((a, b) => b.score.compareTo(a.score));
    return scores;
  }

  /// 查資料 + 排序 + 反查 [Category] 物件,給「建議」分頁直接渲染用。
  /// 沒有任何歷史紀錄時(新帳本冷啟動)退回全部可記帳分類,不排序。
  static Future<List<Category>> getSuggestedCategories({
    required BaseRepository repository,
    required int ledgerId,
    required List<CategoryBudgetUsage> budgetUsages,
    required DateTime now,
    int? contextAccountId,
    String noteText = '',
  }) async {
    final usable = await repository.getUsableCategories('expense');
    final signals = await repository.getCategoryUsageSignals(
      ledgerId: ledgerId,
      kind: 'expense',
      since: now.subtract(historyWindow),
    );
    if (signals.isEmpty) return usable.take(maxSuggestions).toList();

    final scores = computeScores(
      signals: signals,
      budgetUsages: budgetUsages,
      now: now,
      contextAccountId: contextAccountId,
      noteText: noteText,
    );

    final byId = {for (final c in usable) c.id: c};
    final ranked = <Category>[];
    for (final s in scores) {
      final c = byId.remove(s.categoryId);
      if (c != null) ranked.add(c);
    }
    // 有可用分類但完全沒歷史紀錄可比對到的(例如剛新增的分類)排在最後,
    // 維持它們原本(sortOrder)的相對順序。
    ranked.addAll(byId.values);
    return ranked.take(maxSuggestions).toList();
  }
}
