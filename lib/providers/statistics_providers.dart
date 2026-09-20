import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_providers.dart';
import 'ui_state_providers.dart';
import 'currency_providers.dart';
import 'theme_providers.dart' show weekStartsOnMondayProvider;
import '../services/system/logger_service.dart';
import '../utils/net_worth_trend_utils.dart';
import '../utils/overview_chart_utils.dart';

// 统计：账本数量
final ledgerCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖全局统计刷新 tick，确保手动刷新或恢复后能重新计算
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.ledgerCount();
});

// 统计：某账本的记账天数与总笔数
final countsForLedgerProvider = FutureProvider.family
    .autoDispose<({int dayCount, int txCount}), int>((ref, ledgerId) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.getCountsForLedger(ledgerId: ledgerId);
});

// 统计刷新 tick（全局）：每次 +1 触发统计相关 Provider 重新获取
final statsRefreshProvider = StateProvider<int>((ref) => 0);

// 统计：全应用的记账天数与总笔数（跨账本聚合）
final lastCountsAllProvider =
    StateProvider<({int dayCount, int txCount})?>((ref) => null);

final countsAllProvider =
    FutureProvider.autoDispose<({int dayCount, int txCount})>((ref) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发手动刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  final res = await repo.getCountsAll();
  // 写入最近一次成功值，供 UI 在刷新期间显示旧值
  ref.read(lastCountsAllProvider.notifier).state = res;
  return res;
});

// 统计：当前账本总余额
final currentBalanceProvider =
    FutureProvider.family.autoDispose<double, int>((ref, ledgerId) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());

  // 获取账户功能开启状态
  final accountFeatureEnabled =
      await ref.watch(accountFeatureEnabledProvider.future);

  final stats = await repo.getLedgerStats(
    ledgerId: ledgerId,
    accountFeatureEnabled: accountFeatureEnabled,
  );
  return stats.balance;
});

// 统计：月度汇总最近值（避免loading闪烁）
final lastMonthlyTotalsProvider = StateProvider.family<
    (double income, double expense)?,
    ({int ledgerId, DateTime month})>((ref, params) => null);

// 统计：月度汇总（收入、支出）
final monthlyTotalsProvider = FutureProvider.family.autoDispose<
    (double income, double expense),
    ({int ledgerId, DateTime month})>((ref, params) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  final res =
      await repo.monthlyTotals(ledgerId: params.ledgerId, month: params.month);
  // 写入最近一次成功值，供 UI 在刷新期间显示旧值
  ref.read(lastMonthlyTotalsProvider(params).notifier).state = res;
  return res;
});

// 统计：单个账户统计（余额、消费、收入）
final accountStatsProvider = FutureProvider.family
    .autoDispose<({double balance, double expense, double income}), int>(
        (ref, accountId) async {
  final repo = ref.watch(repositoryProvider);
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.getAccountStats(accountId);
});

// 统计：所有账户统计（每个账户的余额、消费、收入）
// v1.15.0: 不再限制账本，获取所有账户
final allAccountStatsProvider = FutureProvider.autoDispose<
    Map<int, ({double balance, double expense, double income})>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  logger.info('AllAccountStats', '使用的 Repository 类型: ${repo.runtimeType}');
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  final stats = await repo.getAllAccountStats();
  logger.info('AllAccountStats', '获取到 ${stats.length} 个账户的统计数据');
  return stats;
});

// 统计：所有账户汇总统计（总余额、总支出、总收入）
// v1.15.0: 不再限制账本，获取所有账户
final allAccountsTotalStatsProvider = FutureProvider.autoDispose<
    ({
      double totalBalance,
      double totalExpense,
      double totalIncome
    })>((ref) async {
  final repo = ref.watch(repositoryProvider);
  logger.info(
      'AllAccountsTotalStats', '使用的 Repository 类型: ${repo.runtimeType}');
  // 依赖 tick 触发刷新
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  final stats = await repo.getAllAccountsTotalStats();
  logger.info('AllAccountsTotalStats',
      '总余额: ${stats.totalBalance}, 总支出: ${stats.totalExpense}, 总收入: ${stats.totalIncome}');
  return stats;
});

// 统计：净资产分解（总资产、总负债、净资产）
final netWorthBreakdownProvider = FutureProvider.autoDispose<
    ({
      double totalAssets,
      double totalLiabilities,
      double netWorth
    })>((ref) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.getNetWorthBreakdown();
});

// 统计：按币种分组的净资产分解
final netWorthBreakdownByCurrencyProvider = FutureProvider.autoDispose<
    Map<String,
        ({double totalAssets, double totalLiabilities, double netWorth})>>(
  (ref) async {
    final repo = ref.watch(repositoryProvider);
    ref.watch(statsRefreshProvider);
    final link = ref.keepAlive();
    ref.onDispose(() => link.close());
    return repo.getNetWorthBreakdownByCurrency();
  },
);

// 统计：净资产每日趋势
final netWorthTrendProvider = FutureProvider.family.autoDispose<
    List<({DateTime date, double balance})>,
    ({DateTime startDate, DateTime endDate})>((ref, params) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.getNetWorthDailyBalances(
      startDate: params.startDate, endDate: params.endDate);
});

/// 净值趋势序列(资产/负债/净资产每日),范围参数化。
final netWorthTrendSeriesProvider = FutureProvider.family.autoDispose<
    List<({DateTime date, double assets, double liabilities, double net})>,
    ({DateTime startDate, DateTime endDate})>((ref, params) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(statsRefreshProvider);
  // 折算到主币种,与净资产卡(convertedNetWorthProvider)同口径:各币种 → base 汇率,
  // base 自身 1.0;缺汇率的币种在 repo 内整条剔除。这样趋势末点 = 当前净资产。
  final base = ref.watch(baseCurrencyProvider).toUpperCase();
  final rates = await ref.watch(effectiveRatesProvider.future);
  final ratesToBase = <String, double>{base: 1.0};
  for (final e in rates.entries) {
    final r = double.tryParse(e.value.rate);
    if (r != null && r > 0) ratesToBase[e.key.toUpperCase()] = r;
  }
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.getNetWorthTrendSeries(
      startDate: params.startDate,
      endDate: params.endDate,
      ratesToBase: ratesToBase);
});

/// 全局最早一笔交易的发生时间（净值趋势「全部」范围的起点）。无交易返回 null。
final earliestTransactionDateProvider =
    FutureProvider.autoDispose<DateTime?>((ref) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(statsRefreshProvider);
  return repo.getEarliestTransactionDate();
});

// 统计：资产构成（按账户类型分组）
final assetCompositionProvider =
    FutureProvider.autoDispose<List<({String type, double totalBalance})>>(
        (ref) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(statsRefreshProvider);
  final link = ref.keepAlive();
  ref.onDispose(() => link.close());
  return repo.getAssetCompositionByType();
});

/// 資產管理頁「走勢」互動組合圖（長條：收入/支出 + 折線：淨資產）的資料源，
/// 依 [OverviewGranularity] 切換視窗大小與聚合方式（見
/// docs/superpowers/specs/2026-09-21-account-overview-moze-chart-design.md
/// 「資料層設計」）。
///
/// 月/年粒度改用現成的 totalsByMonth/totalsByYearSeries（各自查詢效率較好），
/// 而不是統一用 totalsByDay 前端分桶，是為了避免跨年份查詢時撈取大量逐日資料
/// 造成效能浪費；日/週粒度資料量小，用 totalsByDay 前端分桶即可。三種來源分開
/// 呼叫，但輸出統一交給 overview_chart_utils.dart 的純函式聚合成
/// [OverviewChartPoint]，provider 本身只負責 I/O。
final accountOverviewChartSeriesProvider = FutureProvider.family
    .autoDispose<List<OverviewChartPoint>, OverviewGranularity>(
        (ref, granularity) async {
  final repo = ref.watch(repositoryProvider);
  ref.watch(statsRefreshProvider);
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final weekStartsOnMonday = ref.watch(weekStartsOnMondayProvider);
  // 跟 netWorthTrendSeriesProvider 用同一个「今天」锚点：规整到日级，
  // 避免 DateTime.now() 微秒抖动导致 family key 每次都变、provider 永远新建。
  final asOfDate = trendTodayAnchor();
  final windowStart = overviewWindowStart(granularity, asOfDate,
      weekStartsOnMonday: weekStartsOnMonday);

  // 净资产折线：所有粒度共用同一个既有 provider，只是查询范围（family key）
  // 不同，天然各自缓存。折算口径跟净资产卡一致，直接复用不用重新实现汇率折算。
  final netWorthDaily = await ref.watch(
      netWorthTrendSeriesProvider((startDate: windowStart, endDate: asOfDate))
          .future);
  // getNetWorthTrendSeries 在完全没有账户(includeInTotal)时回传空列表——这是
  // 唯一「真的没数据可画」的情形(不是新账本资料不够,是压根没账户)。此时几个
  // builder* 函式仍会照样補出固定长度的零值桶,会把「没数据」误画成一条乎 0
  // 横线,因此提前短路回传空列表,交给 widget 层的 `points.length < 2` 判断
  // 显示既有 commonEmpty 文案(跟旧版 _buildNetWorthChartInline 行为一致)。
  if (netWorthDaily.isEmpty) return const [];

  final link = ref.keepAlive();
  ref.onDispose(() => link.close());

  switch (granularity) {
    case OverviewGranularity.day:
      final income = await repo.totalsByDay(
          ledgerId: ledgerId,
          type: 'income',
          start: windowStart,
          end: asOfDate.add(const Duration(days: 1)));
      final expense = await repo.totalsByDay(
          ledgerId: ledgerId,
          type: 'expense',
          start: windowStart,
          end: asOfDate.add(const Duration(days: 1)));
      return buildDailyOverviewPoints(
          incomeDaily: income,
          expenseDaily: expense,
          netWorthDaily: netWorthDaily,
          asOfDate: asOfDate);

    case OverviewGranularity.week:
      final income = await repo.totalsByDay(
          ledgerId: ledgerId,
          type: 'income',
          start: windowStart,
          end: asOfDate.add(const Duration(days: 1)));
      final expense = await repo.totalsByDay(
          ledgerId: ledgerId,
          type: 'expense',
          start: windowStart,
          end: asOfDate.add(const Duration(days: 1)));
      return buildWeeklyOverviewPoints(
          incomeDaily: income,
          expenseDaily: expense,
          netWorthDaily: netWorthDaily,
          asOfDate: asOfDate,
          weekStartsOnMonday: weekStartsOnMonday);

    case OverviewGranularity.month:
      final year = asOfDate.year;
      final month = asOfDate.month;
      var incomeMonthly = await repo.totalsByMonth(
          ledgerId: ledgerId, type: 'income', year: year);
      var expenseMonthly = await repo.totalsByMonth(
          ledgerId: ledgerId, type: 'expense', year: year);
      // totalsByMonth 回傳整年 1~12 月（未來月份補 0），近 12 個月若跨年需要
      // 再补去年剩下的月份，并把今年里落在「今天」之后的月份滤掉。
      if (month < 12) {
        final prevIncome = await repo.totalsByMonth(
            ledgerId: ledgerId, type: 'income', year: year - 1);
        final prevExpense = await repo.totalsByMonth(
            ledgerId: ledgerId, type: 'expense', year: year - 1);
        incomeMonthly = [...prevIncome, ...incomeMonthly];
        expenseMonthly = [...prevExpense, ...expenseMonthly];
      }
      final cutoff = DateTime(year, month, 1);
      incomeMonthly =
          incomeMonthly.where((e) => !e.month.isAfter(cutoff)).toList();
      expenseMonthly =
          expenseMonthly.where((e) => !e.month.isAfter(cutoff)).toList();
      return buildMonthlyOverviewPoints(
          incomeMonthly: incomeMonthly,
          expenseMonthly: expenseMonthly,
          netWorthDaily: netWorthDaily,
          asOfDate: asOfDate);

    case OverviewGranularity.year:
      final incomeYearly =
          await repo.totalsByYearSeries(ledgerId: ledgerId, type: 'income');
      final expenseYearly =
          await repo.totalsByYearSeries(ledgerId: ledgerId, type: 'expense');
      return buildYearlyOverviewPoints(
          incomeYearly: incomeYearly,
          expenseYearly: expenseYearly,
          netWorthDaily: netWorthDaily,
          asOfDate: asOfDate);
  }
});
