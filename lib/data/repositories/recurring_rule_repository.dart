import '../db.dart';

/// [RecurringRuleRepository.materializeDueTransferRules] 裡「因餘額不足被
/// 跳過」的單筆記錄。Repository 層只管資料/生成邏輯,**不直接彈通知**(同
/// [Transactions]/[Accounts] 等表一樣,repository 不該碰
/// `flutter_local_notifications` 這種平台/UI 層依賴)——呼叫端(App 啟動時
/// 跑生成引擎的 service 層)拿這個列表自己決定怎麼通知使用者。
class RecurringRuleTransferSkip {
  final int ruleId;
  final String? note;
  final DateTime occurrenceAt;
  final double requiredAmount;
  final double currentBalance;

  const RecurringRuleTransferSkip({
    required this.ruleId,
    required this.note,
    required this.occurrenceAt,
    required this.requiredAmount,
    required this.currentBalance,
  });
}

/// 週期性收支規則 Repository 接口。取代舊版 `RecurringTransactionRepository`
/// (純本地、不同步)。對齊 BeeCount Cloud 的 `recurring_rule` sync entity,
/// 見 `docs/CLOUD_SYNC_INTEGRATION.md` 與
/// `docs/changes/2026-08-17-recurring-transactions-cloud-sync.md`。
///
/// **沒有獨立的「單期(occurrence)」概念**:規則只定義循環方式,每一期發生
/// 的交易就是 [Transactions] 表裡帶 `recurringRuleId` 的普通列——所以這個
/// 接口既有「規則本身」的 CRUD,也有「規則產生的 occurrence 交易」該怎麼
/// 編輯/刪除(「此記錄」vs「連同未來週期」)的方法。
abstract class RecurringRuleRepository {
  // ============ 規則 CRUD / 查詢 ============

  /// 建立規則,並依 [RecurringTransactionSchedule] 的視窗策略當場批次生成
  /// 初始 occurrence 交易(有 `endAt` 全部生成;沒有則生成預設視窗,之後靠
  /// [refillWindows] 續產生)。`type == 'transfer'` 的規則**不**在這裡预生成
  /// (自動扣繳語意,見 [materializeDueTransferRules]),只建規則本身。
  /// 回傳新規則的本地 id。
  Future<int> createRule({
    required int ledgerId,
    required String type, // expense / income / transfer
    required double amount,
    int? categoryId,
    int? accountId, // expense/income 用
    int? fromAccountId, // transfer 來源帳戶
    int? toAccountId, // transfer 目標帳戶
    String? note,
    String? merchant,
    List<String> tagSyncIds = const [],
    List<String> rewardRuleSyncIds = const [],
    required String frequency, // daily/weekly/monthly/yearly
    int interval = 1,
    Map<String, dynamic>? advancedRule,
    required DateTime nextRunAt,
    DateTime? endAt,
  });

  Future<RecurringTransaction?> getRuleById(int id);
  Future<RecurringTransaction?> getRuleBySyncId(String syncId);
  Future<List<RecurringTransaction>> getRulesByLedger(int ledgerId);
  Future<List<RecurringTransaction>> getAllRulesForExport();

  Stream<List<RecurringTransaction>> watchRulesByLedger(int ledgerId);

  /// 引用該帳戶的**進行中**(enabled=true)規則數量(轉出/轉入/收支任一端命
  /// 中即算)。帳戶隱藏確認框用此數提示「有 N 個週期帳單在用此帳戶」,同舊版
  /// `getActiveRecurringCountByAccount` 語意。
  Future<int> getActiveRuleCountByAccount(int accountId);

  // ============ 「此記錄」vs「連同未來週期」 ============

  /// 「修改此記錄」:只更新這一筆 occurrence 交易,標記
  /// `recurringOccurrenceOverridden = true`,不動規則本身、不影響其它期。
  /// [transactionId] 是本地 int id(單筆交易的常規標識)。
  Future<void> updateOccurrence({
    required int transactionId,
    String? type,
    double? amount,
    int? categoryId,
    int? accountId,
    int? toAccountId,
    String? note,
    String? merchant,
    List<String>? tagSyncIds,
    List<String>? rewardRuleSyncIds,
  });

  /// 「刪除此記錄」:只刪這一筆 occurrence 交易,不影響規則、不影響其它期。
  Future<void> deleteOccurrence(int transactionId);

  /// 「修改連同未來週期」:更新規則本身(供以後新生成的期數延用新值)+ 批次
  /// 更新同規則、`happenedAt >= anchor.happenedAt`、且未被單獨編輯過
  /// (`recurringOccurrenceOverridden == false`)的既有 occurrence 交易(不動
  /// `happenedAt`,只改內容)。[anchorTransactionId] 是使用者點進去操作的那
  /// 一筆,用它的 `happenedAt` 當批次更新的起點。
  Future<void> updateRuleAndFuture({
    required int ruleId,
    required int anchorTransactionId,
    String? type,
    double? amount,
    int? categoryId,
    int? accountId,
    int? fromAccountId,
    int? toAccountId,
    String? note,
    String? merchant,
    List<String>? tagSyncIds,
    List<String>? rewardRuleSyncIds,
    String? frequency,
    int? interval,
    Map<String, dynamic>? advancedRule,
  });

  /// 「刪除連同未來週期」:刪除同規則、`happenedAt > now` 的所有 occurrence
  /// 交易(不論是否被單獨編輯過——已發生的、含使用者手動改過的都保留不動),
  /// 規則標記 `enabled = false`(規則列本身不刪,只是不再產生新的期數)。
  Future<void> terminateFuture(int ruleId);

  /// 刪除整條規則(從規則列表頁的「刪除規則」入口進來,不是從某一筆
  /// occurrence 進來)。[deleteFutureOccurrences] true 時連同尚未發生的
  /// occurrence 一起刪(已發生的一律保留),對齊 Cloud
  /// `DELETE .../recurring-rules/{id}` 的 `delete_future_occurrences` 語意。
  Future<void> deleteRule(int ruleId, {bool deleteFutureOccurrences = true});

  // ============ 生成引擎(App 啟動時呼叫) ============

  /// 視窗續產生:掃 `enabled=true` 且 `generatedUntilAt` 快到期的非 transfer
  /// 規則,往前補一個視窗。回傳實際生成的 occurrence 筆數,涉及的 ledgerId
  /// 集合(供呼叫端觸發同步)。
  Future<({int generatedCount, Set<int> ledgerIds})> refillWindows();

  /// transfer 類型(自動扣繳)規則:到期當下才逐筆生成,生成前查來源帳戶當
  /// 下記帳餘額,不夠就跳過(不推進進度,下次呼叫重試同一期)。回傳實際生成
  /// 筆數、被跳過的明細(供呼叫端通知使用者)、涉及的 ledgerId 集合。
  Future<({int materialized, List<RecurringRuleTransferSkip> skipped, Set<int> ledgerIds})>
      materializeDueTransferRules();
}
