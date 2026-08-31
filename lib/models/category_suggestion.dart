/// 「建議」分頁排序演算法用的單筆歷史使用訊號，來自
/// [TransactionRepository.getCategoryUsageSignals]。
class CategoryUsageSignal {
  final int categoryId;
  final DateTime happenedAt;
  final int? accountId;
  final String? note;

  const CategoryUsageSignal({
    required this.categoryId,
    required this.happenedAt,
    this.accountId,
    this.note,
  });
}

/// 單一分類的建議分數，附帶各訊號分解值方便除錯/測試。
class CategorySuggestionScore {
  final int categoryId;
  final double score;
  final double recencyFreq;
  final double timeOfDay;
  final double dayOfWeek;
  final double accountContext;
  final double noteText;
  final double budgetPenalty;

  const CategorySuggestionScore({
    required this.categoryId,
    required this.score,
    required this.recencyFreq,
    required this.timeOfDay,
    required this.dayOfWeek,
    required this.accountContext,
    required this.noteText,
    required this.budgetPenalty,
  });
}
