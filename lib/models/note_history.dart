/// 系統自動產生、使用者從未手動輸入過的備註固定前綴——歷史備註清單不該
/// 收錄這些(使用者不是「打過這個字」,只是剛好觸發了會寫這種備註的自動
/// 流程)。信用卡回饋入帳由 BeeCount Cloud 端結算時寫入(見該倉庫
/// `src/services/card_reward_payout.py`/`src/routers/write/card_reward_rules.py`
/// 的 `信用卡回饋入帳：`/`信用卡回饋入帳（手動）：` 開頭),信用卡繳款由本機
/// `creditCardPaymentNote()`(`lib/utils/credit_card_payment.dart`)產生。
const kSystemGeneratedNotePrefixes = <String>[
  '信用卡回饋入帳',
  '信用卡繳款(帳單',
];

/// 历史备注的查询范围。
enum NoteHistoryScope {
  /// 查询当前账本全部分类。
  allCategories,

  /// 仅查询当前选中的具体分类。
  currentCategory,
}

/// 历史备注的排序规则。
enum NoteHistorySort {
  /// 按累计使用次数排序。
  frequency,

  /// 按最近一次使用时间排序。
  recent,
}

/// 历史备注聚合结果。
class NoteHistoryEntry {
  /// 去除首尾空白后的备注文本。
  final String note;

  /// 当前查询范围内的累计使用次数。
  final int usageCount;

  const NoteHistoryEntry({
    required this.note,
    required this.usageCount,
  });
}
