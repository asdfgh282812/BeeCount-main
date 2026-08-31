/// 商家欄位「依類別記住常用商家」的聚合結果。
///
/// 跟 [NoteHistoryEntry](note_history.dart) 同款形狀,但商家沒有 note 的
/// scope/sort 使用者可調設定——恆按分類過濾(沒有分類就不過濾)、恆按使用
/// 次數由高到低排序,不需要一份對稱的 enum。
class MerchantHistoryEntry {
  /// 去除首尾空白後的商家文本。
  final String merchant;

  /// 當前查詢範圍內的累計使用次數。
  final int usageCount;

  const MerchantHistoryEntry({
    required this.merchant,
    required this.usageCount,
  });
}
