import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/db.dart';
import '../data/repositories/base_repository.dart';
import '../models/card_reward_summary.dart';
import '../utils/card_reward_calc.dart';
import '../utils/card_reward_period.dart';
import 'database_providers.dart';

/// 撈某規則在 [start, end] 這一段內套用的交易,算出這一段自己的彙總——不管
/// 這段是「規則自己的完整週期」還是「橫跨帳單週期時拆出來的單一自然月」,
/// 都是同一份查詢/加總邏輯,見呼叫處 [_summarizeRulePeriod]。
Future<CardRewardRuleSummary> _summarizeRulePeriod(
  BaseRepository repo,
  CardRewardRule rule,
  int accountId,
  List<int>? extraIds,
  DateTime start,
  DateTime end,
) async {
  final txs = await repo.getAccountTransactions(
    accountId,
    limit: 1000,
    offset: 0,
    extraAccountIds: extraIds,
    startDate: start,
    endDate: end,
  );
  final matched = rule.syncId == null
      ? const <Transaction>[]
      : txs.where((t) => t.rewardRuleIds.contains(rule.syncId)).toList();
  // matched 是由新到舊排序(見上方查詢),累計扣減額度要照交易發生時間由舊到
  // 新才對,所以另外排一份升冪清單餵給 estimateCardRewardCumulative。
  final ascending = List<Transaction>.from(matched)
    ..sort((a, b) => a.happenedAt.compareTo(b.happenedAt));
  final rewardByTransactionId = estimateCardRewardCumulative(rule, ascending);
  var totalReward = 0.0;
  var totalSpend = 0.0;
  for (final tx in matched) {
    totalReward += rewardByTransactionId[tx.id] ?? 0;
    if (tx.type == 'expense') totalSpend += tx.amount.abs();
  }
  return CardRewardRuleSummary(
    rule: rule,
    periodStart: start,
    periodEnd: end,
    transactions: matched,
    totalReward: totalReward,
    rewardByTransactionId: rewardByTransactionId,
    totalSpend: totalSpend,
  );
}

/// 規則的檢視視窗一律是帳戶的帳單週期(offset 導覽跟帳戶頁「交易明細」tab
/// 的帳單彙總卡片對齊,同一顆帳單週期一起往前往後翻)。若規則是以「自然月」
/// 算上限(interval == calendar_month)而這顆帳單週期橫跨多個自然月,上限
/// 會跟著自然月重置,所以拆成每個自然月各自查詢/加總(見
/// [splitPeriodByCalendarMonth]),[CardRewardRuleSummary.monthlyBreakdown] 放
/// 各自然月的子彙總,外層 totalReward/totalSpend 是這些子彙總的合計、
/// periodStart/End 是整顆帳單週期的起訖。interval == billing_cycle 或視窗本來
/// 就沒跨自然月時 monthlyBreakdown 是 null,跟原本行為一致。
Future<CardRewardRuleSummary> _summarizeRuleWindow(
  BaseRepository repo,
  CardRewardRule rule,
  int accountId,
  List<int>? extraIds,
  int? billingDay,
  int offset,
) async {
  final window = billingCyclePeriod(billingDay, offset);
  if (rule.interval != 'calendar_month') {
    return _summarizeRulePeriod(
        repo, rule, accountId, extraIds, window.start, window.end);
  }
  final months = splitPeriodByCalendarMonth(window.start, window.end);
  if (months.length <= 1) {
    return _summarizeRulePeriod(
        repo, rule, accountId, extraIds, window.start, window.end);
  }
  final breakdown = <CardRewardRuleSummary>[];
  var totalReward = 0.0;
  var totalSpend = 0.0;
  final allTxs = <Transaction>[];
  final rewardByTransactionId = <int, double>{};
  for (final month in months) {
    final part = await _summarizeRulePeriod(
        repo, rule, accountId, extraIds, month.start, month.end);
    breakdown.add(part);
    totalReward += part.totalReward;
    totalSpend += part.totalSpend;
    allTxs.addAll(part.transactions);
    rewardByTransactionId.addAll(part.rewardByTransactionId);
  }
  return CardRewardRuleSummary(
    rule: rule,
    periodStart: window.start,
    periodEnd: window.end,
    transactions: allTxs,
    totalReward: totalReward,
    rewardByTransactionId: rewardByTransactionId,
    totalSpend: totalSpend,
    monthlyBreakdown: breakdown,
  );
}

/// 某信用卡帐户下的全部紅利回饋規則(含已停用),按 sortOrder 排序。
/// list 頁 + 記帳表單的回饋選單共用同一個 provider,底层 Drift watch 流,
/// 資料變動自動 rebuild,不需要额外的 refresh trigger。
final cardRewardRulesForAccountProvider =
    StreamProvider.family<List<CardRewardRule>, int>((ref, accountId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchCardRewardRulesForAccount(accountId);
});

/// 單一紅利回饋規則詳情(编辑页回填用)。
final cardRewardRuleByIdProvider =
    FutureProvider.family<CardRewardRule?, int>((ref, id) async {
  final repo = ref.watch(repositoryProvider);
  return repo.getCardRewardRuleById(id);
});

/// 某信用卡帳戶下所有「啟用中」規則,各自在 [offset] 帳單週期內套用的交易與
/// 估算回饋彙總;interval == calendar_month 且該帳單週期橫跨多個自然月時
/// 拆成 [CardRewardRuleSummary.monthlyBreakdown],見 [_summarizeRuleWindow]。
/// 帳戶詳情頁「交易明細」tab 的紅利回饋分組卡片用這個——[offset] 要傳呼叫端
/// 目前選取的帳單週期導覽 offset(跟帳單彙總卡片的 `_billingPeriodOffset`
/// 同一個值,不是固定 0),否則切換帳期看到的回饋金額會跟畫面上顯示的帳期
/// 對不上(2026-08-18 bugfix)。
final cardRewardAccountSummaryProvider = FutureProvider.family.autoDispose<
    List<CardRewardRuleSummary>,
    ({int accountId, String extraIdsKey, int? billingDay, int offset})>(
  (ref, params) async {
    final repo = ref.watch(repositoryProvider);
    final rules = (await ref
            .watch(cardRewardRulesForAccountProvider(params.accountId).future))
        .where((r) => r.enabled)
        .toList();
    final extraIds = params.extraIdsKey.isEmpty
        ? null
        : params.extraIdsKey.split(',').map(int.parse).toList();
    final result = <CardRewardRuleSummary>[];
    for (final rule in rules) {
      result.add(await _summarizeRuleWindow(
        repo,
        rule,
        params.accountId,
        extraIds,
        params.billingDay,
        params.offset,
      ));
    }
    return result;
  },
);

/// 紅利回饋明細頁用:單一規則在指定 [offset] 帳單週期(可前後翻頁,跟帳戶彙
/// 總卡片固定看 offset 0 不同)的套用交易與估算彙總,同樣依 interval 決定要
/// 不要拆自然月,見 [_summarizeRuleWindow]。
final cardRewardRulePeriodSummaryProvider = FutureProvider.family.autoDispose<
    CardRewardRuleSummary,
    ({
      CardRewardRule rule,
      int accountId,
      String extraIdsKey,
      int? billingDay,
      int offset
    })>(
  (ref, params) async {
    final repo = ref.watch(repositoryProvider);
    final extraIds = params.extraIdsKey.isEmpty
        ? null
        : params.extraIdsKey.split(',').map(int.parse).toList();
    return _summarizeRuleWindow(
      repo,
      params.rule,
      params.accountId,
      extraIds,
      params.billingDay,
      params.offset,
    );
  },
);
