import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart' as db;
import '../data/repositories/base_repository.dart';
import '../providers.dart';
import '../utils/card_reward_period.dart';
import '../utils/credit_card_payment.dart';

/// 信用卡繳款(MOZE 對標)規則一/規則二/帳戶列表徽章共用的帳戶餘額
/// provider——都建立在 `AccountRepository.getCreditCardChargedAsOf`/
/// `getCreditCardPaidTotal` 之上,鏡射 BeeCount Cloud
/// `compute_cycle_period_billing` 的 `max(charged_as_of(cutoff) - paid_total, 0)`
/// watermark 公式(`paidTotal` 終身不設 cutoff,不論繳款發生在哪個帳期都先
/// 套用在最早未清償的帳期上)。**不要**改回用 `getAccountBalance`/
/// `getCreditCardUsedAmount`——那兩個方法會混入 `initialBalance`/轉出/
/// adjustment,這些在 Cloud 的信用卡帳單公式裡都不存在,對不上會導致 App
/// 端數字比 Server 端多算或少算(2026-08-18 bugfix)。
///
/// [extraIdsKey]:同 `reconciliation_providers.dart::accountStatementTransactionsProvider`
/// 的慣例,主帳戶(合併帳單群組)的子帳戶 id 清單、逗號分隔且已排序,空字串
/// = 沒有子帳戶。

List<int> _parseExtraIds(String extraIdsKey) => extraIdsKey.isEmpty
    ? const <int>[]
    : extraIdsKey.split(',').map(int.parse).toList();

/// 算 [ids] 加總後在 [cutoff] 這個時間點的「仍欠款」金額(正值=欠款,對齊
/// Cloud `remaining_due`/`carryover_due` 的正負號),[cutoff] 為 null 時退化成
/// 只看 `paidTotal`(不太會發生,呼叫端一律會傳 cutoff)。
///
/// 子專案 4(帳單分期沖銷):`charged` 要先扣掉
/// [InstallmentRepository.getOffsetTotalForAccount]——已經被某個分期計畫
/// `offsetExistingBalance` 沖銷掉的既有欠款,不管 [cutoff] 是哪個時間點都要
/// 扣(對齐 Cloud `compute_offset_totals` docstring:「沖銷代表從此以後這筆
/// 帳從卡片上移除,對建立分期計畫之後的任何 cutoff 都成立」),否則這筆錢
/// 會同時算在「這張卡的原始消費」跟「新分期計畫產生的各期交易」兩邊,重複
/// 計入應繳金額。
Future<double> _dueAsOf(
  BaseRepository repo,
  List<int> ids,
  DateTime cutoff,
) async {
  var charged = 0.0;
  var paidTotal = 0.0;
  for (final id in ids) {
    charged += await repo.getCreditCardChargedAsOf(id, asOf: cutoff);
    charged -= await repo.getOffsetTotalForAccount(id);
    paidTotal += await repo.getCreditCardPaidTotal(id);
  }
  return creditCardDueAsOf(charged: charged, paidTotal: paidTotal);
}

/// 規則一:進入信用卡「交易明細」tab 時預設停留的帳期 offset——「尚未繳清
/// 的最早歷史帳期」,全部繳清時回傳 0(當期)。
final defaultBillingPeriodOffsetProvider = FutureProvider.family
    .autoDispose<int, ({int accountId, String extraIdsKey, int? billingDay})>(
  (ref, params) async {
    ref.watch(syncGenerationProvider);
    // 問題 B 修正(2026-09-03,見
    // docs/changes/2026-09-03-installment-tracking-delete-sync-fixes.md):
    // `_dueAsOf` 讀 `getOffsetTotalForAccount`(分期帳單沖銷),但建立/刪除
    // 分期計畫這種**本地寫入**只 bump `installmentsRefreshProvider`,不會
    // bump `syncGenerationProvider`(那個只在遠端 pull 真的 apply 到東西時
    // 才 bump,見 sync_providers.dart 的 PullCompleted 分支)。純 watch
    // syncGenerationProvider 涵蓋不到「本機建立/刪除一筆帶沖銷的分期計畫」
    // 這個情境,這裡補上。
    ref.watch(installmentsRefreshProvider);
    final repo = ref.watch(repositoryProvider);
    final ids = [params.accountId, ..._parseExtraIds(params.extraIdsKey)];

    Future<double> balanceOwedAsOf(int offset) async {
      final period = billingCyclePeriod(params.billingDay, offset);
      return _dueAsOf(repo, ids, endOfDay(period.end));
    }

    return findEarliestUnpaidPeriodOffset(balanceOwedAsOf: balanceOwedAsOf);
  },
);

/// 規則二:帳戶(或群組所有子帳戶加總)在某個時間點的「仍欠款」快照,以
/// 帳單彙總卡片既有的號位慣例回傳(負值代表欠款、正值代表溢繳——目前
/// watermark 公式已清償/溢繳時一律回傳 0,溢繳結轉本身不在這個 provider
/// 的職責內)。用於「上期欠款」列(`asOf` 傳上一期期末)跟「剩餘帳款」/
/// 新增還款預帶金額(`asOf` 傳這一期期末)。
final accountBalanceAsOfProvider = FutureProvider.family
    .autoDispose<double, ({int accountId, String extraIdsKey, DateTime asOf})>(
  (ref, params) async {
    ref.watch(syncGenerationProvider);
    // 問題 B 修正(2026-09-03)——理由同 [defaultBillingPeriodOffsetProvider]
    // 上方的說明:本地建立/刪除帶沖銷的分期計畫不會 bump
    // syncGenerationProvider,這裡補上 installmentsRefreshProvider。
    ref.watch(installmentsRefreshProvider);
    final repo = ref.watch(repositoryProvider);
    final ids = [params.accountId, ..._parseExtraIds(params.extraIdsKey)];
    final due = await _dueAsOf(repo, ids, params.asOf);
    return -due;
  },
);

/// [_periodNewSpend] 的期末減期初算法,見 [creditCardPaymentPeriodRecordsProvider]。
Future<double> _periodNewSpend(
  BaseRepository repo,
  List<int> ids,
  int? billingDay,
  int offset,
) async {
  final period = billingCyclePeriod(billingDay, offset);
  var chargedEnd = 0.0;
  var chargedStart = 0.0;
  for (final id in ids) {
    chargedEnd +=
        await repo.getCreditCardChargedAsOf(id, asOf: endOfDay(period.end));
    chargedStart += await repo.getCreditCardChargedAsOf(id,
        asOf: startOfDayExclusivePrior(period.start));
  }
  return chargedEnd - chargedStart;
}

/// 「繳款記錄」清單顯示用(帳戶詳情頁「交易明細」tab):[targetOffset] 這個
/// 帳期實際被沖銷到的繳款交易明細——依入帳歸屬日新到舊排序。**這是 App 端
/// 專屬的顯示行為,不是鏡射 Cloud**(`get_account_statement` 是單純日期窗口
/// 查詢,沒有這種歸屬概念),對帳模式(`accountStatementTransactionsProvider`)
/// 跟帳單彙總卡片的「已繳金額」/「剩餬帳款」數字都不受這個 provider 影響,
/// 只影響「繳款記錄」小節本身要顯示哪幾筆交易(2026-08-18:使用者明確要求
/// 「雖然是在 8/11–9/11 這期繳費,但我繳的是上一期的費用,所以繳款記錄應該
/// 放到 7/11–8/11」,見
/// `docs/changes/2026-08-18-credit-card-payment-record-attribution-restore.md`)。
///
/// 1. 用 [AccountRepository.getCreditCardFirstActivityAt](合併帳單群組要對
///    每個子帳戶都查,取最早的一個)找出模擬要往回展開到多舊的帳期——這個
///    起點之前保證沒有任何交易,`priorCarryDue` 用 0 當起點是精確值。
/// 2. 模擬範圍是這個起點到「當期」(offset 0),每期的 `newSpend` 用
///    [_periodNewSpend] 算。
/// 3. 把這張卡(+ 群組子卡)全部繳款交易依入帳歸屬日排序,餵給
///    `attributePaymentsToPeriods`。
/// 4. 篩出歸屬到 [targetOffset] 的交易,依入帳歸屬日新到舊排序回傳。
///
/// **不要**改用 `getCreditCardPaidTotal`(終身不設 cutoff 的加總)當某個
/// offset 的 `priorCarryDue` 快照再另外處理「之後」的繳款——同一筆繳款會被
/// 算兩次,踩過這個陷阱的完整說明見
/// `docs/changes/2026-08-18-credit-card-payment-period-attribution-fix.md`
/// 「開發過程中修正的兩個重複計算陷阱」一節。
final creditCardPaymentPeriodRecordsProvider = FutureProvider.family
    .autoDispose<
        List<db.Transaction>,
        ({
          int accountId,
          String extraIdsKey,
          int? billingDay,
          int targetOffset
        })>((ref, params) async {
  ref.watch(syncGenerationProvider);
  final repo = ref.watch(repositoryProvider);
  final ids = [params.accountId, ..._parseExtraIds(params.extraIdsKey)];

  DateTime? firstActivity;
  for (final id in ids) {
    final at = await repo.getCreditCardFirstActivityAt(id);
    if (at != null && (firstActivity == null || at.isBefore(firstActivity))) {
      firstActivity = at;
    }
  }
  if (firstActivity == null) return const [];

  var oldestOffset = 0;
  while (billingCyclePeriod(params.billingDay, oldestOffset)
      .start
      .isAfter(firstActivity)) {
    oldestOffset -= 1;
    if (oldestOffset < -600) break;
  }
  if (params.targetOffset < oldestOffset) return const [];

  final periods = <({int periodId, double newSpend})>[
    for (var offset = oldestOffset; offset <= 0; offset++)
      (
        periodId: offset,
        newSpend: await _periodNewSpend(repo, ids, params.billingDay, offset),
      ),
  ];

  final allPayments = <db.Transaction>[
    for (final id in ids) ...await repo.getCreditCardPaymentTransactions(id),
  ]..sort((a, b) => (a.deferredPostingAt ?? a.happenedAt)
      .compareTo(b.deferredPostingAt ?? b.happenedAt));

  final home = attributePaymentsToPeriods(
    periods: periods,
    payments: [
      for (final tx in allPayments) (paymentId: tx.id, amount: tx.amount),
    ],
  );

  final result = allPayments
      .where((tx) => home[tx.id] == params.targetOffset)
      .toList()
    ..sort((a, b) => (b.deferredPostingAt ?? b.happenedAt)
        .compareTo(a.deferredPostingAt ?? a.happenedAt));
  return result;
});

/// 帳戶列表「可繳款」徽章用:某張卡(含其合併帳單子卡)在「最近一次已結帳
/// 週期」的剩餘應繳金額(正值=欠款)跟繳款截止日,鏡射 Cloud
/// `routers/read/workspace.py::list_workspace_accounts` 的
/// `billing_due_date`/`billing_remaining_due` 邏輯——只在 `remainingDue > 0.01`
/// 時才顯示徽章,沒有額外的「N 天內」時間窗口限制。沒設 billingDay/
/// paymentDueDay 時回傳 null(不顯示)。
final creditCardBillingBadgeProvider = FutureProvider.family.autoDispose<
    ({double remainingDue, DateTime dueDate})?,
    ({
      int accountId,
      String extraIdsKey,
      int? billingDay,
      int? paymentDueDay,
    })>(
  (ref, params) async {
    if (params.billingDay == null || params.paymentDueDay == null) {
      return null;
    }
    ref.watch(syncGenerationProvider);
    // 問題 B 修正(2026-09-03)——理由同上。
    ref.watch(installmentsRefreshProvider);
    final repo = ref.watch(repositoryProvider);
    final ids = [params.accountId, ..._parseExtraIds(params.extraIdsKey)];
    final offset = mostRecentlyClosedBillingOffset(params.billingDay);
    final period = billingCyclePeriod(params.billingDay, offset);
    final due = await _dueAsOf(repo, ids, endOfDay(period.end));
    if (due <= 0.01) return null;
    return (
      remainingDue: due,
      dueDate: creditCardPaymentDueDate(period.end, params.paymentDueDay!),
    );
  },
);
