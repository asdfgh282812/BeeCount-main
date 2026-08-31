import '../../data/repositories/base_repository.dart';
import '../../models/merchant_history.dart';

/// 商家欄位「依類別記住常用商家」服務。
///
/// 跟 [NoteHistoryService](note_history_service.dart) 同款結構,但沒有
/// scope/sort 使用者可調設定——恆按分類過濾(沒有有效分類就退回帳本全部
/// 分類,避免轉帳等沒有分類的場景拿到空結果),恆按使用次數排序。
class MerchantHistoryService {
  static Future<List<MerchantHistoryEntry>> getHistoryMerchants({
    required BaseRepository repository,
    required int ledgerId,
    int? categoryId,
    String? categorySyncId,
    int limit = 20,
  }) async {
    final shouldFilterByCategory =
        categoryId != null || (categorySyncId?.isNotEmpty ?? false);
    return repository.getMerchantHistory(
      ledgerId: ledgerId,
      categoryId: shouldFilterByCategory ? categoryId : null,
      categorySyncId: shouldFilterByCategory ? categorySyncId : null,
      limit: limit,
    );
  }
}
