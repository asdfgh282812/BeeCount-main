/// 記帳表單「同帳戶+同類別自動代入回饋規則」的本機學習快取接口。
///
/// 只在使用者手動於回饋規則選單選擇/清空時寫入,SwipeSmart 雲端卡片推薦
/// 點選不寫入(它沒有對應到本機 [CardRewardRule.syncId]),詳見
/// `RewardChoiceCaches` 表定義注釋與 `TransactionEntryFormState`
/// 裡 `_openRewardRuleSelector`/`_maybeAutoApplyRewardCache` 的呼叫點。
abstract class RewardChoiceCacheRepository {
  /// 讀取「類別+帳戶」上次使用者選擇的回饋規則 syncId 清單。從未設定過時
  /// 回傳 null。呼叫端(`_maybeAutoApplyRewardCache`)對 null 跟空清單一視
  /// 同仁(都是「沒有可自動套用的東西」),所以 [clearRewardChoice] 直接刪列
  /// 而不是存一筆空陣列——語意上等同「回到從未設定過」。
  Future<List<String>?> getCachedRewardRuleIds({
    required int ledgerId,
    required int categoryId,
    required int accountId,
  });

  /// 寫入/覆蓋這組「類別+帳戶」的選擇(存在則更新,不存在則新建)。
  Future<void> upsertRewardChoice({
    required int ledgerId,
    required int categoryId,
    required int accountId,
    required List<String> rewardRuleIds,
  });

  /// 清空這組「類別+帳戶」的快取紀錄(直接刪列)。
  Future<void> clearRewardChoice({
    required int ledgerId,
    required int categoryId,
    required int accountId,
  });
}
